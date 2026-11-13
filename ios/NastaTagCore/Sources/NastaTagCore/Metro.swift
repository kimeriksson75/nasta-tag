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
}

public func estimateWalkMinutes(from: Coordinate, to: Coordinate) -> Double {
    distanceMeters(from, to) * 1.3 / 80 // gångvägen är längre än fågelvägen, 80 m i minuten
}
