import Foundation

public struct Station: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var siteId: Int
    public var lat: Double
    public var lon: Double
    public var id: Int { siteId }
    public var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
}

public struct MetroRoute: Codable, Hashable, Sendable {
    public var color: String
    public var stations: [String]
}

/// Tunnelbanans stationer och linjer, samma data som webbappen använder.
public struct Metro: Codable, Sendable {
    public var stations: [Station]
    public var routes: [MetroRoute]

    public static let stockholm: Metro = {
        let url = Bundle.module.url(forResource: "metro", withExtension: "json")!
        return try! JSONDecoder().decode(Metro.self, from: Data(contentsOf: url))
    }()

    public func nearestStations(to position: Coordinate, count: Int = 1) -> [Station] {
        Array(stations.sorted { distanceMeters(position, $0.coordinate) < distanceMeters(position, $1.coordinate) }.prefix(count))
    }

    /// Ett tåg från `from` mot slutstationen `destination` passerar `target` om target ligger
    /// efter from och senast vid destination på någon sträcka.
    public func trainReaches(from: String, destination: String, target: String) -> Bool {
        routes.contains { route in
            guard let start = route.stations.firstIndex(of: from),
                  let end = route.stations.firstIndex(of: destination),
                  let stop = route.stations.firstIndex(of: target),
                  start != stop else { return false }
            return start < end ? start < stop && stop <= end : end <= stop && stop < start
        }
    }

    func stopsBetween(_ a: String, _ b: String) -> Int {
        routes.compactMap { route -> Int? in
            guard let i = route.stations.firstIndex(of: a), let j = route.stations.firstIndex(of: b) else { return nil }
            return abs(i - j)
        }.min() ?? Int.max / 4
    }

    /// Alla linjefärger möts vid T-Centralen, så ett byte räcker alltid.
    public func planTrip(from: String, to goal: String) -> (target: String, transfer: String?) {
        if stopsBetween(from, goal) < Int.max / 4 { return (goal, nil) }
        let names = Array(Set(routes.flatMap(\.stations))).sorted()
        let best = names.min { stopsBetween(from, $0) + stopsBetween($0, goal) < stopsBetween(from, $1) + stopsBetween($1, goal) }!
        return (best, best)
    }
}

public func estimateWalkMinutes(from: Coordinate, to: Coordinate) -> Double {
    distanceMeters(from, to) * 1.3 / 80 // gångvägen är längre än fågelvägen, 80 m i minuten
}
