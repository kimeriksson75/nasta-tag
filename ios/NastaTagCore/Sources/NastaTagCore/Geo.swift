import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

public func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
    let dLat = radians(b.lat - a.lat)
    let dLon = radians(b.lon - a.lon)
    let h = pow(sin(dLat / 2), 2) + cos(radians(a.lat)) * cos(radians(b.lat)) * pow(sin(dLon / 2), 2)
    return 2 * 6_371_000 * asin(sqrt(h))
}

/// Riktning från a till b i grader medurs från norr.
public func bearingDegrees(_ a: Coordinate, _ b: Coordinate) -> Double {
    let dLon = radians(b.lon - a.lon)
    let y = sin(dLon) * cos(radians(b.lat))
    let x = cos(radians(a.lat)) * sin(radians(b.lat)) - sin(radians(a.lat)) * cos(radians(b.lat)) * cos(dLon)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

public func distanceText(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
    return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
}
