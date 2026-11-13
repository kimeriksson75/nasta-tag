import Foundation

/// En destination: en adress och dess punkt på kartan.
/// Platser sparade av äldre versioner har bara en tunnelbanestation; de får stationens punkt.
public struct Place: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var station: String?
    public var weekdaysOnly: Bool
    public var address: String?
    public var coordinate: Coordinate?
    public init(id: String = UUID().uuidString, label: String, station: String? = nil, weekdaysOnly: Bool = false,
                address: String? = nil, coordinate: Coordinate? = nil) {
        self.id = id
        self.label = label
        self.station = station
        self.weekdaysOnly = weekdaysOnly
        self.address = address
        self.coordinate = coordinate
    }

    /// Det som visas under namnet i inställningarna.
    public var detail: String { address ?? station ?? "" }
}

/// Ger äldre platser, som bara har en station, stationens punkt.
public func migratePlaces(_ places: [Place], metro: Metro) -> [Place] {
    places.map { place in
        guard place.coordinate == nil, let name = place.station,
              let station = metro.stations.first(where: { $0.name == name }) else { return place }
        var place = place
        place.coordinate = station.coordinate
        return place
    }
}

/// Samma ruta som servern godtar: Stockholms län med lite marginal.
public func isInStockholm(_ point: Coordinate) -> Bool {
    (58.6...60.4).contains(point.lat) && (17.2...19.6).contains(point.lon)
}

/// Så här nära en destination räknas du som framme.
public let atPlaceMeters = 400.0

/// Destinationen du står vid, om du är nära någon.
public func placeAt(_ places: [Place], position: Coordinate, meters: Double = atPlaceMeters) -> String? {
    places.compactMap { place in place.coordinate.map { (place.id, distanceMeters(position, $0)) } }
        .filter { $0.1 < meters }
        .min { $0.1 < $1.1 }?.0
}

/// Bara vardagar: appen föreslår inte destinationen på helgen, men du kan fortfarande välja den själv.
public func isAvailable(_ place: Place, now: Date, calendar: Calendar = .current) -> Bool {
    !place.weekdaysOnly || !calendar.isDateInWeekend(now)
}

/// När du är framme blir nästa destination aktiv, så Hem ger Jobbet och tvärtom.
/// Annars ligger valet kvar. `chosenId` är det du själv valt, det gäller tills du är framme.
public func nextDestination(_ places: [Place], activeId: String?, hereId: String?, now: Date, chosenId: String? = nil) -> Place? {
    guard let active = places.first(where: { $0.id == activeId }) ?? places.first else { return nil }
    let open = { (place: Place) in isAvailable(place, now: now) }
    if active.id != hereId && (open(active) || active.id == chosenId) { return active }
    let index = places.firstIndex(of: active)!
    let others = Array(places[(index + 1)...] + places[..<index])
    return others.first { $0.id != hereId && open($0) }
        ?? ([active] + others).first { $0.id == hereId && open($0) }
        ?? active
}
