import Foundation

// Resor med alla trafikslag från SL:s reseplanerare, samma regler som webbappen.

/// Trafikslag i SL:s reseplanerare: hur linjen skrivs och vad avgången kallas i löpande text.
public struct Mode: Sendable {
    public var line: String
    public var noun: String

    public init(_ productClass: Int) {
        switch productClass {
        case 0: (line, noun) = ("Pendeltåg", "pendeltåget")
        case 2: (line, noun) = ("Linje", "tåget")
        case 4: (line, noun) = ("Spårvagn", "spårvagnen")
        case 5: (line, noun) = ("Buss", "bussen")
        case 9: (line, noun) = ("Båt", "båten")
        default: (line, noun) = ("Linje", "avgången")
        }
    }

    static func isWalk(_ productClass: Int?) -> Bool { productClass == 99 || productClass == 100 }
}

/// Hållplatsen där du kliver på.
public struct Stop: Codable, Hashable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    public init(name: String, lat: Double, lon: Double) {
        self.name = name
        self.lat = lat
        self.lon = lon
    }
}

/// En resa, kortad till det appen behöver. Du ska gå när första delen börjar,
/// och första fordonet är det som visas stort.
public struct Trip: Hashable, Sendable, Identifiable {
    public var key: String
    public var leaveAt: Date
    public var time: Date
    public var arrival: Date
    public var mode: Int
    public var line: String
    public var towards: String
    public var stop: Stop
    public var walkMinutes: Double
    public var walkMeters: Double
    public var transfers: [String]
    public var slackMinutes: Double = 0
    public var status: Status = .calm
    public var id: String { key }

    public var lineText: String { "\(Mode(mode).line) \(line) mot \(towards)" }
}

// MARK: SL:s svar

public struct Journey: Decodable, Sendable {
    public var legs: [Leg]

    public struct Leg: Decodable, Sendable {
        var transportation: Transportation?
        var origin: Point
        var destination: Point
        var distance: Double?
        var realtimeStatus: [String]?
    }

    struct Transportation: Decodable, Sendable {
        struct Product: Decodable, Sendable {
            var productClass: Int?
            enum CodingKeys: String, CodingKey { case productClass = "class" }
        }
        struct Destination: Decodable, Sendable { var name: String? }
        var id: String?
        var disassembledName: String?
        var number: String?
        var product: Product?
        var destination: Destination?
    }

    struct Point: Decodable, Sendable {
        struct Parent: Decodable, Sendable {
            var disassembledName: String?
            var coord: [Double]?
        }
        var name: String?
        var disassembledName: String?
        var coord: [Double]?
        var parent: Parent?
        var departureTimePlanned: String?
        var departureTimeEstimated: String?
        var arrivalTimePlanned: String?
        var arrivalTimeEstimated: String?

        var stopName: String {
            parent?.disassembledName ?? disassembledName
                ?? name?.replacingOccurrences(of: ", Stockholm", with: "") ?? ""
        }
        var departure: Date? { slDate(departureTimeEstimated ?? departureTimePlanned) }
        var arrival: Date? { slDate(arrivalTimeEstimated ?? arrivalTimePlanned) }
    }
}

struct JourneysResponse: Decodable { var journeys: [Journey]? }

private func slDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: text) { return date }
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: text)
}

private func isWalk(_ leg: Journey.Leg) -> Bool { Mode.isWalk(leg.transportation?.product?.productClass) }

/// Inställda resor och resor utan fordon räknas inte.
public func parseJourney(_ journey: Journey) -> Trip? {
    let legs = journey.legs
    guard let ride = legs.firstIndex(where: { !isWalk($0) }),
          !legs.contains(where: { ($0.realtimeStatus ?? []).contains { $0.contains("CANCELLED") } }),
          let transportation = legs[ride].transportation,
          let first = legs.first, let last = legs.last,
          let leaveAt = first.origin.departure,
          let time = legs[ride].origin.departure,
          let arrival = last.destination.arrival,
          let coord = legs[ride].origin.parent?.coord ?? legs[ride].origin.coord, coord.count == 2
    else { return nil }
    let origin = legs[ride].origin
    return Trip(
        key: "\(transportation.id ?? "")|\(origin.departureTimePlanned ?? "")",
        leaveAt: leaveAt,
        time: time,
        arrival: arrival,
        mode: transportation.product?.productClass ?? -1,
        line: transportation.disassembledName ?? transportation.number ?? "",
        towards: transportation.destination?.name ?? "",
        stop: Stop(name: origin.stopName, lat: coord[0], lon: coord[1]),
        walkMinutes: time.timeIntervalSince(leaveAt) / 60,
        walkMeters: legs[..<ride].reduce(0) { $0 + ($1.distance ?? 0) },
        transfers: legs[(ride + 1)...].filter { !isWalk($0) }.map(\.origin.stopName)
    )
}

/// Resorna med marginal och färg. Samma avgång kan komma flera gånger, den räknas en gång.
public func buildTrips(_ journeys: [Journey], now: Date) -> [Trip] {
    var seen = Set<String>()
    return journeys.compactMap(parseJourney)
        .filter { seen.insert($0.key).inserted }
        .map { trip in
            var trip = trip
            trip.slackMinutes = trip.leaveAt.timeIntervalSince(now) / 60
            trip.status = classify(trip.slackMinutes)
            return trip
        }
        .sorted { $0.leaveAt < $1.leaveAt }
}

/// Snabbast fram vinner bland resorna du hinner med. Kommer två fram samtidigt
/// väljs den du kan gå senare till, och de andra visas som fler avgångar.
public func pickTrips(_ trips: [Trip]) -> (next: Trip?, later: [Trip]) {
    let open = trips.filter { $0.status != .missed }
    let next = open.reduce(nil as Trip?) { best, trip in
        guard let best else { return trip }
        return trip.arrival < best.arrival || (trip.arrival == best.arrival && trip.leaveAt > best.leaveAt) ? trip : best
    }
    return (next, open.filter { $0.key != next?.key })
}

// MARK: Hämta

public enum TripsError: Error { case status(Int) }

private let tripsURL = "https://journeyplanner.integration.sl.se/v2/trips"
private let maxTrips = 3 // mer än så svarar SL inte med

private func slPlace(_ point: Coordinate) -> String {
    String(format: "%.5f:%.5f:WGS84[dd.ddddd]", point.lon, point.lat)
}

/// Resor härifrån till destinationen med alla trafikslag, med uppdaterade tider.
/// Med `departAt` börjar listan vid den tiden i stället för nu.
public func fetchJourneys(from: Coordinate, to: Coordinate, departAt: Date? = nil) async throws -> [Journey] {
    var components = URLComponents(string: tripsURL)!
    components.queryItems = [
        .init(name: "type_origin", value: "coord"),
        .init(name: "name_origin", value: slPlace(from)),
        .init(name: "type_destination", value: "coord"),
        .init(name: "name_destination", value: slPlace(to)),
        .init(name: "calc_number_of_trips", value: String(maxTrips)),
    ]
    if let departAt {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
        formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: departAt)
        formatter.dateFormat = "HHmm"
        components.queryItems! += [.init(name: "itd_date", value: date), .init(name: "itd_time", value: formatter.string(from: departAt))]
    }
    var request = URLRequest(url: components.url!)
    request.timeoutInterval = 15
    for attempt in 0..<4 {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return try JSONDecoder().decode(JourneysResponse.self, from: data).journeys ?? [] }
        // SL:s öppna API svarar ibland 429 på enstaka anrop; nästa brukar gå igenom.
        guard code == 429, attempt < 3 else { throw TripsError.status(code) }
        try await Task.sleep(for: .seconds(1.5 * Double(attempt + 1)))
    }
    throw TripsError.status(429)
}

/// Reseplaneraren låter gången till hållplatsen börja före den tid man frågar om, så när det är
/// nära och tätt mellan avgångarna kan alla svar redan ha gått. Då frågar vi vidare från den
/// senaste avgången tills det finns några att visa.
public func fetchUpcomingJourneys(from: Coordinate, to: Coordinate, now: Date, wanted: Int = 3) async throws -> [Journey] {
    var all = try await fetchJourneys(from: from, to: to)
    for _ in 0..<2 {
        let trips = buildTrips(all, now: now)
        guard trips.filter({ $0.status != .missed }).count < wanted, let latest = trips.map(\.time).max() else { break }
        all += try await fetchJourneys(from: from, to: to, departAt: latest.addingTimeInterval(60))
    }
    return all
}
