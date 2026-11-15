import ActivityKit
import CoreLocation
import MapKit
import NastaTagCore
import Observation
import SwiftUI

/// Appens tillstånd: var du är, vart du ska och resorna dit med alla trafikslag från SL:s reseplanerare.
@MainActor
@Observable
final class AppModel: NSObject, CLLocationManagerDelegate {
    let metro = Metro.stockholm

    var places: [Place] { didSet { save() } }
    var activeId: String? { didSet { save() } }
    private var chosenId: String?

    var position: Coordinate?
    var heading: Double?
    /// Platsen du står vid, om du är nära någon.
    private(set) var hereId: String?
    private var journeys: [Journey]?
    /// Resor som börjar vid den följda avgången, ifall den har fallit ur de vanliga resultaten.
    private var followedJourneys: [Journey] = []
    var problem: String?
    var locationDenied = false
    var now = Date()
    var fetchedAt: Date?
    private(set) var following: Activity<TripAttributes>?
    private var followedStatus: Status?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var ticker: Timer?
    private var fetching = false
    /// Varifrån och vart de senaste resorna hämtades.
    private var fetchedFrom: Coordinate?
    private var fetchedFor: String?

    private static let placesKey = "places"
    private static let activeKey = "activeId"
    private static let refreshSeconds: TimeInterval = 30
    private static let retrySeconds: TimeInterval = 10
    private static let movedMeters = 40.0 // gå så här långt innan resorna räknas om
    private static let nearStopMeters = 30.0

    override init() {
        let saved = UserDefaults.standard.data(forKey: Self.placesKey)
        let decoded = saved.flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        places = migratePlaces(decoded, metro: Metro.stockholm)
        activeId = UserDefaults.standard.string(forKey: Self.activeKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 2
        TripActions.snooze = { [weak self] in self?.toggleSnoozeFollowed() }
        TripActions.stopFollowing = { [weak self] in self?.unfollow() }
        TripActions.askSkip = { [weak self] in self?.askSkipFollowed() }
        TripActions.answerSkip = { [weak self] skip in self?.answerSkipFollowed(skip) }
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

    /// Efter en ändring i inställningarna eller när appen kommer fram igen.
    func refreshSoon() {
        fetchedAt = nil
        tick()
    }

    private func tick() {
        now = Date()
        chooseDestination()
        forgetOldSnoozes()
        noticeMissed()
        if needsRefresh { Task { await refreshTrips() } } else { updateFollowing() }
    }

    private var needsRefresh: Bool {
        guard let position, let destination else { return false }
        guard let fetchedAt, let fetchedFrom, fetchedFor == destination.id else { return true }
        if distanceMeters(fetchedFrom, position) >= Self.movedMeters { return true }
        // Har alla resor gått behövs nya direkt, inte om en halv minut.
        let wait = next == nil && journeys != nil ? Self.retrySeconds : Self.refreshSeconds
        return now.timeIntervalSince(fetchedAt) >= wait
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
        let first = position == nil
        position = coordinate
        if first { tick() }
    }

    // MARK: Destination

    var destination: Place? { places.first { $0.id == activeId } ?? places.first }

    /// Hem ger Jobbet och tvärtom när du är framme. Ett eget val gäller tills du är framme.
    private func chooseDestination() {
        hereId = position.flatMap { placeAt(places, position: $0) }
        guard let next = nextDestination(places, activeId: activeId, hereId: hereId, now: now, chosenId: chosenId) else { return }
        if next.id != activeId { activeId = next.id; snoozed = nil; missed = nil; shownKey = nil }
        if let chosenId, chosenId == hereId { self.chosenId = nil }
    }

    func choose(_ place: Place) {
        snoozed = nil
        missed = nil
        shownKey = nil
        chosenId = place.id
        activeId = place.id
        refreshSoon()
    }

    /// Platser du kan välja: alla utom den du står vid.
    var destinations: [Place] { places.filter { $0.id != hereId } }

    // MARK: Resor

    private var trips: [Trip] { buildTrips(journeys ?? [], now: now) }
    private var picked: (next: Trip?, later: [Trip]) {
        pickTrips(trips.filter { trip in snoozed.map { trip.leaveAt > $0.leaveAt } ?? true })
    }

    // MARK: Snooze

    /// Avgången du har snoozat. Bara en åt gången: Snooze-knappen slår av och på.
    private(set) var snoozed: Trip?

    /// Resan du får om du snoozar: den bästa av dem som går senare än den du har nu.
    var snoozeTarget: Trip? { next.flatMap(target(after:)) }

    private func target(after trip: Trip) -> Trip? {
        pickTrips(trips.filter { $0.leaveAt > trip.leaveAt }).next
    }

    /// Hur mycket senare du kan gå om du snoozar, i hela minuter.
    var snoozeMinutes: Int? { next.flatMap(snoozeMinutes(for:)) }

    private func snoozeMinutes(for trip: Trip) -> Int? {
        guard let later = target(after: trip) else { return nil }
        return max(1, Int((later.leaveAt.timeIntervalSince(trip.leaveAt) / 60).rounded()))
    }

    /// Snoozar avgången du har nu, eller ångrar snoozen om du redan har en.
    func toggleSnooze() {
        if snoozed != nil {
            snoozed = nil
        } else {
            guard let next, snoozeTarget != nil else { return }
            snoozed = next
        }
        countSnooze(undo: snoozed == nil)
        retargetFollowing()
    }

    /// Från låsskärmen gäller knappen resan som syns där, även om appen hunnit välja en annan.
    func toggleSnoozeFollowed() {
        if snoozed != nil { return toggleSnooze() }
        let followed = following?.content.state.key
        guard let trip = trips.first(where: { $0.key == followed }) ?? next, target(after: trip) != nil else { return }
        snoozed = trip
        countSnooze(undo: false)
        retargetFollowing()
    }

    // MARK: Missad

    /// Hur länge appen visar att du missade innan den går vidare till nästa avgång.
    static let missedSeconds: TimeInterval = 15
    /// Avgången du nyss missade, och när appen går vidare av sig själv.
    private(set) var missed: (trip: Trip, until: Date)?
    /// Avgången som visades vid förra ticket, så att appen märker när den blir missad.
    private var shownKey: String?

    /// När tiden att gå tar slut visas avgången som missad en stund, med frågan om du bryr dig,
    /// i stället för att appen hoppar direkt till nästa.
    private func noticeMissed() {
        if let missed, now >= missed.until || missed.trip.time < now.addingTimeInterval(-60) { self.missed = nil }
        if missed == nil, let shownKey, next?.key != shownKey,
           let trip = trips.first(where: { $0.key == shownKey }), trip.status == .missed, !isSkipped {
            missed = (trip, now.addingTimeInterval(Self.missedSeconds))
        }
        shownKey = missed == nil ? next?.key : nil
    }

    /// Gå vidare till nästa avgång direkt.
    func dismissMissed() {
        missed = nil
        shownKey = next?.key
    }

    // MARK: Strunta i resan

    private static let skipKey = "skippedDay"
    /// Destinationen och dagen du har struntat i, "jobb|2026-11-15". Gäller till midnatt.
    private var skippedDay = UserDefaults.standard.string(forKey: "skippedDay")
    /// Hur många gånger du har snoozat mot den här destinationen idag.
    private var snoozeTally: (day: String, count: Int)?
    /// Orden efteråt, valda när du tryckte så att de står still.
    private(set) var skipDone: String?

    private var dayKey: String? { destination.map { "\($0.id)|\(stockholmDay(now))" } }

    private func countSnooze(undo: Bool) {
        guard let dayKey else { return }
        let count = snoozeTally?.day == dayKey ? snoozeTally!.count : 0
        snoozeTally = (dayKey, max(0, count + (undo ? -1 : 1)))
    }

    /// Du har struntat i resan dit idag.
    var isSkipped: Bool { dayKey != nil && skippedDay == dayKey }

    /// Har du redan snoozat en gång idag byter Snooze-knappen till att strunta i resan.
    var offerSkip: Bool {
        guard !isSkipped, snoozed == nil, next != nil, let dayKey, let snoozeTally else { return false }
        return snoozeTally.day == dayKey && snoozeTally.count >= 1
    }

    var skipWords: SkipWords? {
        guard let trip = missed?.trip ?? next, let destination else { return nil }
        return NastaTagCore.skipWords(label: destination.label, trainTime: trip.time, mode: trip.mode)
    }

    /// Slutar påminna om resan dit idag: notiserna slutar, och låsskärmen säger det en stund innan den försvinner.
    func skipToday() {
        // Samma ord som låsskärmen visar, som gäller den följda avgången.
        if let followed = following?.content.state, let destination {
            skipDone = NastaTagCore.skipWords(label: destination.label, trainTime: followed.trainTime, mode: followed.mode).done
        } else {
            skipDone = skipWords?.done ?? "Okej. Vi hörs i morgon."
        }
        skippedDay = dayKey
        UserDefaults.standard.set(skippedDay, forKey: Self.skipKey)
        snoozed = nil
        missed = nil
        askingSkip = false
        guard let activity = following else { return }
        var last = activity.content.state
        last.skipped = true
        last.askingSkip = false
        stopFollowing()
        Task { await activity.end(.init(state: last, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(30))) }
    }

    /// Låsskärmen frågar innan den struntar i resan.
    private(set) var askingSkip = false

    func askSkipFollowed() {
        guard offerSkip else { return }
        askingSkip = true
        pushFollowed()
    }

    func answerSkipFollowed(_ skip: Bool) {
        if skip { return skipToday() }
        askingSkip = false
        pushFollowed()
    }

    /// Visar ändringen på låsskärmen direkt, utan att vänta på nästa tick.
    private func pushFollowed() {
        guard let activity = following else { return }
        let followed = activity.content.state
        guard let trip = trips.first(where: { $0.key == followed.key }) ?? next else { return }
        Task { await activity.update(.init(state: state(for: trip), staleDate: trip.time)) }
    }

    /// Ångrar: avgångarna visas igen och Snooze börjar om.
    func unskip() {
        skippedDay = nil
        UserDefaults.standard.removeObject(forKey: Self.skipKey)
        snoozeTally = nil
    }

    /// En snooze glöms när avgången du hoppade över har gått, då finns inget att ångra.
    private func forgetOldSnoozes() {
        if let snoozed, snoozed.time < now { self.snoozed = nil }
    }

    /// Följer du en resa på låsskärmen följer låsskärmen med till den nya.
    private func retargetFollowing() {
        guard let activity = following, let next else { return }
        followedStatus = next.status
        followedJourneys = []
        Task { await activity.update(.init(state: state(for: next), staleDate: next.time)) }
    }

    var next: Trip? { picked.next }
    var later: [Trip] { Array(picked.later.prefix(3)).sorted { $0.time < $1.time } }

    /// Det som står i stället för resan när något saknas.
    var blocker: String? {
        if places.isEmpty { return "Lägg till ditt hem för att komma igång." }
        if locationDenied { return "Appen behöver din plats för att hitta vägen." }
        guard position != nil else { return "Letar efter var du är …" }
        guard let destination else { return nil }
        if destination.id == hereId { return "Du är redan vid \(destination.label)." }
        if let problem { return problem }
        guard journeys != nil, fetchedFor == destination.id else { return "Hämtar avgångar …" }
        return next == nil ? "Inga avgångar du hinner med just nu." : nil
    }

    private func refreshTrips() async {
        guard let position, let destination, let target = destination.coordinate, !fetching else { return }
        fetching = true
        defer { fetching = false }
        do {
            let fresh = try await fetchUpcomingJourneys(from: position, to: target, now: Date())
            guard self.destination?.id == destination.id else { return }
            if fetchedFor != destination.id { walkRoute = nil }
            journeys = fresh
            fetchedFrom = position
            fetchedFor = destination.id
            fetchedAt = Date()
            problem = nil
            await refreshFollowed(from: position, to: target, fresh: fresh)
        } catch {
            problem = "Får inget svar från SL just nu."
            fetchedAt = Date().addingTimeInterval(-Self.refreshSeconds + Self.retrySeconds) // försök igen om en stund
            fetchedFrom = position
            fetchedFor = destination.id
        }
        now = Date()
        updateFollowing()
    }

    /// Den följda avgången kan falla ur reseplanerarens tre bästa. Då frågar vi från strax före den.
    private func refreshFollowed(from position: Coordinate, to target: Coordinate, fresh: [Journey]) async {
        guard let followed = following?.content.state else { return followedJourneys = [] }
        if buildTrips(fresh, now: now).contains(where: { $0.key == followed.key }) { return followedJourneys = [] }
        followedJourneys = (try? await fetchJourneys(from: position, to: target,
                                                     departAt: followed.trainTime.addingTimeInterval(-2 * 60))) ?? []
    }

    // MARK: Gången till hållplatsen

    /// Hållplatsen där nästa resa börjar.
    var stop: Stop? { next?.stop }

    /// Gångvägens längd när den finns, annars fågelvägen. Nil när du redan står där.
    var stopDistance: Double? {
        guard let next, let position else { return nil }
        let straight = distanceMeters(position, next.stop.coordinate)
        guard straight >= Self.nearStopMeters else { return nil }
        return next.walkMeters > 0 ? next.walkMeters : straight
    }

    /// Hur pilen ska vridas för att peka mot hållplatsen, eller nil utan kompass.
    var arrowAngle: Double? {
        guard let stop, let position, let heading else { return nil }
        return bearingDegrees(position, stop.coordinate) - heading
    }

    /// Gångvägen till hållplatsen för kartan i appen. Hämtas om när du har gått en bit.
    var walkRoute: MKRoute?
    private var walkRouteFrom: Coordinate?
    private var walkRouteTo: Stop?

    func loadWalkRoute() async {
        guard let stop, let position else { return }
        if walkRouteTo == stop, let walkRouteFrom, distanceMeters(walkRouteFrom, position) < Self.movedMeters { return }
        if walkRouteTo != stop { walkRoute = nil }
        walkRouteFrom = position
        walkRouteTo = stop
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: position.lat, longitude: position.lon)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: stop.lat, longitude: stop.lon)))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first,
              self.stop == walkRouteTo else { return }
        walkRoute = route
    }

    // MARK: Live Activity

    var canFollow: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private func state(for trip: Trip) -> TripAttributes.ContentState {
        TripAttributes.ContentState(status: trip.status, leaveBy: trip.leaveAt, trainTime: trip.time,
                                    line: trip.lineText, towards: trip.towards, station: trip.stop.name,
                                    key: trip.key, mode: trip.mode, minutes: minutesToLeave(trip.slackMinutes),
                                    snoozeMinutes: snoozeMinutes(for: trip), snoozed: snoozed != nil,
                                    offerSkip: offerSkip, askingSkip: askingSkip)
    }

    /// Visar resan på låsskärmen och i Dynamic Island tills den har gått.
    func follow() {
        guard let next, let destination else { return }
        do {
            following = try Activity.request(attributes: TripAttributes(label: destination.label),
                                             content: .init(state: state(for: next), staleDate: next.time))
            followedStatus = next.status
            followedJourneys = []
            resumeBackground()
        } catch {
            problem = "Kunde inte visa resan på låsskärmen."
        }
    }

    func unfollow() {
        let activity = following
        stopFollowing()
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Medan du följer en resa håller platsen appen vaken i bakgrunden, så att färgen och minuterna kan bytas.
    private func resumeBackground() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
    }

    private func stopFollowing() {
        following = nil
        askingSkip = false
        followedStatus = nil
        followedJourneys = []
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.allowsBackgroundLocationUpdates = false
    }

    private func updateFollowing() {
        guard let activity = following else { return }
        guard activity.activityState == .active else { return stopFollowing() }
        let followed = activity.content.state
        let known = buildTrips((journeys ?? []) + followedJourneys, now: now)
        guard let trip = known.first(where: { $0.key == followed.key }), trip.status != .missed else {
            // Bara när avgången faktiskt har gått: annars väntar vi på nästa svar från SL.
            guard now > followed.trainTime || followed.leaveBy.timeIntervalSince(now) < -60 else { return }
            var last = followed
            last.status = .missed
            stopFollowing()
            Task { await activity.end(.init(state: last, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(120))) }
            return
        }
        let state = state(for: trip)
        guard state != followed else { return }
        let worse = followedStatus.map { urgency(trip.status) > urgency($0) } ?? false
        followedStatus = trip.status
        let alert = worse ? AlertConfiguration(
            title: "\(departureMessage(trip).headline)",
            body: "\(alertBody(status: trip.status, minutes: state.minutes, trainTime: trip.time, mode: trip.mode, label: activity.attributes.label))",
            sound: .default) : nil
        Task { await activity.update(.init(state: state, staleDate: trip.time), alertConfiguration: alert) }
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
