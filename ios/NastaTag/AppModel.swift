import ActivityKit
import CoreLocation
import MapKit
import NastaTagCore
import Observation
import SwiftUI

/// Närmaste station och hur långt det är dit till fots.
struct Start: Equatable {
    var station: Station
    var walkMinutes: Double
    var walkMeters: Double?
    var estimated: Bool
}

@MainActor
@Observable
final class AppModel: NSObject, CLLocationManagerDelegate {
    let metro = Metro.stockholm

    var places: [Place] { didSet { save() } }
    var activeId: String? { didSet { save() } }
    private var chosenId: String?

    var position: Coordinate?
    var heading: Double?
    var start: Start?
    var departures: [Departure]?
    var problem: String?
    var locationDenied = false
    var now = Date()
    var fetchedAt: Date?
    private(set) var following: Activity<TripAttributes>?
    private var followedStatus: Status?

    private let manager = CLLocationManager()
    private var walkedFrom: Coordinate?
    private var backgroundSession: CLBackgroundActivitySession?
    private var ticker: Timer?
    private var fetching = false

    private static let placesKey = "places"
    private static let activeKey = "activeId"
    private static let refreshSeconds: TimeInterval = 30
    private static let movedMeters = 75.0 // gå så här långt innan stationen räknas om
    private static let nearStationMeters = 30.0

    override init() {
        let saved = UserDefaults.standard.data(forKey: Self.placesKey)
        places = saved.flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        activeId = UserDefaults.standard.string(forKey: Self.activeKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 2
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(places), forKey: Self.placesKey)
        UserDefaults.standard.set(activeId, forKey: Self.activeKey)
    }

    func begin() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        following = Activity<TripAttributes>.activities.first { $0.activityState == .active }
        if let following {
            followedStatus = following.content.state.status
            resumeBackground()
        }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func refreshSoon() {
        fetchedAt = nil
        tick()
    }

    private func tick() {
        now = Date()
        chooseDestination()
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.refreshSeconds { return updateFollowing() }
        Task { await refreshDepartures() }
    }

    // MARK: Plats

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { return }
        let coordinate = Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        Task { @MainActor in self.onPosition(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = heading }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.locationDenied = status == .denied || status == .restricted }
    }

    private func onPosition(_ coordinate: Coordinate) {
        position = coordinate
        if let walkedFrom, distanceMeters(walkedFrom, coordinate) < Self.movedMeters { return }
        walkedFrom = coordinate
        Task { await findStart(from: coordinate) }
    }

    /// Fågelvägen ljuger vid vatten, så jämför gångvägen till de tre närmaste stationerna.
    private func findStart(from position: Coordinate) async {
        var best: Start?
        for station in metro.nearestStations(to: position, count: 3) {
            guard let walk = await walk(from: position, to: station) else { continue }
            if best == nil || walk.walkMinutes < best!.walkMinutes { best = walk }
        }
        let station = metro.nearestStations(to: position)[0]
        let found = best ?? Start(station: station, walkMinutes: estimateWalkMinutes(from: position, to: station.coordinate),
                                  walkMeters: nil, estimated: true)
        let changed = found.station != start?.station
        start = found
        chooseDestination()
        if changed {
            departures = nil
            await refreshDepartures()
        }
    }

    private func walk(from position: Coordinate, to station: Station) async -> Start? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: position.lat, longitude: position.lon)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: station.lat, longitude: station.lon)))
        request.transportType = .walking
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return Start(station: station, walkMinutes: eta.expectedTravelTime / 60, walkMeters: eta.distance, estimated: false)
    }

    // MARK: Destination och tåg

    var destination: Place? { places.first { $0.id == activeId } ?? places.first }

    /// Hem ger Jobbet och tvärtom när du är framme. Ett eget val gäller tills du är framme.
    private func chooseDestination() {
        guard let start, let next = nextDestination(places, activeId: activeId, stationName: start.station.name,
                                                    now: now, chosenId: chosenId) else { return }
        if next.id != activeId { activeId = next.id }
        if let chosenId, places.first(where: { $0.id == chosenId })?.station == start.station.name { self.chosenId = nil }
    }

    func choose(_ place: Place) {
        chosenId = place.id
        activeId = place.id
    }

    /// Knappar behövs bara när det finns ett val: inte för platsen du är på,
    /// och inte för den enda andra destinationen om appen redan valt den.
    var choices: [Place] {
        guard let start else { return [] }
        let choices = places.filter { $0.station != start.station.name }
        return choices.count == 1 && choices[0].id == activeId ? [] : choices
    }

    var plan: (target: String, transfer: String?)? {
        guard let start, let destination, start.station.name != destination.station else { return nil }
        return metro.planTrip(from: start.station.name, to: destination.station)
    }

    var board: [Train] {
        guard let start, let plan, let departures else { return [] }
        return buildBoard(departures: departures, metro: metro, from: start.station.name, target: plan.target,
                          now: now, walkMinutes: start.walkMinutes)
            .filter { $0.status != .missed }
    }

    var next: Train? { board.first }
    var later: [Train] { Array(board.dropFirst().prefix(3)) }

    /// Det som står i stället för tåget när något saknas.
    var blocker: String? {
        if places.isEmpty { return "Lägg till ditt hem för att komma igång." }
        if locationDenied { return "Appen behöver din plats för att hitta närmaste station." }
        guard let start, let destination else { return "Letar efter närmaste station …" }
        if start.station.name == destination.station { return "Du är redan vid \(destination.label)." }
        if let problem { return problem }
        guard departures != nil else { return "Hämtar avgångar …" }
        return next == nil ? "Inga tåg du hinner med just nu." : nil
    }

    var routeText: String? {
        guard let start, let destination, let plan else { return nil }
        let walk = "\(start.estimated ? "ca " : "")\(max(1, Int(start.walkMinutes.rounded()))) min gång"
        return [walk, start.station.name, plan.transfer.map { "byt vid \($0)" }, destination.label]
            .compactMap { $0 }.joined(separator: " → ")
    }

    /// Gångvägens längd när den finns, annars fågelvägen.
    var stationDistance: Double? {
        guard let start, let position else { return nil }
        guard distanceMeters(position, start.station.coordinate) >= Self.nearStationMeters else { return nil }
        return start.walkMeters ?? distanceMeters(position, start.station.coordinate)
    }

    /// Hur pilen ska vridas för att peka mot stationen, eller nil utan kompass.
    var arrowAngle: Double? {
        guard let start, let position, let heading else { return nil }
        return bearingDegrees(position, start.station.coordinate) - heading
    }

    /// Gångvägen till stationen för kartan i appen. Hämtas om när du har gått en bit.
    var walkRoute: MKRoute?
    private var walkRouteFrom: Coordinate?
    private var walkRouteTo: String?

    func loadWalkRoute() async {
        guard let start, let position else { return }
        if walkRouteTo == start.station.name, let walkRouteFrom, distanceMeters(walkRouteFrom, position) < 40 { return }
        if walkRouteTo != start.station.name { walkRoute = nil }
        walkRouteFrom = position
        walkRouteTo = start.station.name
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: position.lat, longitude: position.lon)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: start.station.lat, longitude: start.station.lon)))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first,
              self.start?.station.name == walkRouteTo else { return }
        walkRoute = route
    }

    private struct DeparturesResponse: Decodable { var departures: [Departure] }

    private func refreshDepartures() async {
        guard let start, !fetching else { return }
        fetching = true
        defer { fetching = false }
        let url = URL(string: "https://transport.integration.sl.se/v1/sites/\(start.station.siteId)/departures?transport=METRO")!
        for attempt in 0..<4 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // SL:s öppna API svarar ibland 429 på enstaka anrop; nästa brukar gå igenom.
                if code == 429 && attempt < 3 {
                    try await Task.sleep(for: .seconds(1.5 * Double(attempt + 1)))
                    continue
                }
                guard code == 200 else { throw URLError(.badServerResponse) }
                guard self.start?.station == start.station else { return }
                departures = try JSONDecoder().decode(DeparturesResponse.self, from: data).departures
                fetchedAt = Date()
                problem = nil
                break
            } catch {
                problem = "Får inget svar från SL just nu."
                fetchedAt = Date().addingTimeInterval(-Self.refreshSeconds + 10) // försök igen om en stund
                break
            }
        }
        now = Date()
        updateFollowing()
    }

    // MARK: Live Activity

    var canFollow: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private func state(for train: Train) -> TripAttributes.ContentState {
        TripAttributes.ContentState(status: train.status, leaveBy: train.leaveBy, trainTime: train.time,
                                    line: train.line, towards: train.destination, station: start?.station.name ?? "",
                                    journey: train.journey)
    }

    /// Visar tåget på låsskärmen och i Dynamic Island tills det har gått.
    func follow() {
        guard let next, let destination else { return }
        do {
            following = try Activity.request(attributes: TripAttributes(label: destination.label),
                                             content: .init(state: state(for: next), staleDate: next.time))
            followedStatus = next.status
            resumeBackground()
        } catch {
            problem = "Kunde inte visa tåget på låsskärmen."
        }
    }

    func unfollow() {
        let activity = following
        stopFollowing()
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Medan du följer ett tåg håller platsen appen vaken i bakgrunden, så att färgen kan bytas.
    private func resumeBackground() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
    }

    private func stopFollowing() {
        following = nil
        followedStatus = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.allowsBackgroundLocationUpdates = false
    }

    private func updateFollowing() {
        guard let activity = following else { return }
        guard activity.activityState == .active else { return stopFollowing() }
        let followed = activity.content.state
        let train = board.first { followed.journey != nil ? $0.journey == followed.journey : $0.time == followed.trainTime }
        guard let train else {
            // Tåget har gått eller finns inte längre: låt beskedet ligga kvar en stund och avsluta.
            var last = activity.content.state
            last.status = .missed
            stopFollowing()
            Task { await activity.end(.init(state: last, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(120))) }
            return
        }
        let state = state(for: train)
        guard state != activity.content.state else { return }
        let worse = followedStatus.map { urgency(train.status) > urgency($0) } ?? false
        followedStatus = train.status
        let alert = worse ? AlertConfiguration(title: "\(activityLead(train.status))",
                                               body: "\(departureMessage(train).wait) till \(train.time.formatted(date: .omitted, time: .shortened))-tåget",
                                               sound: .default) : nil
        Task { await activity.update(.init(state: state, staleDate: train.time), alertConfiguration: alert) }
    }

    private func urgency(_ status: Status) -> Int {
        switch status {
        case .calm: 0
        case .hurry: 1
        case .rush: 2
        case .missed: 3
        }
    }
}
