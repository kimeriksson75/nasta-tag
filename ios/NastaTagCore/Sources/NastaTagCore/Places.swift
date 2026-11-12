import Foundation

/// En destination: en adress och tunnelbanestationen närmast den.
/// Äldre sparade platser har bara station, därför är adressen frivillig.
public struct Place: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var station: String
    public var weekdaysOnly: Bool
    public var address: String?
    public var coordinate: Coordinate?
    public init(id: String = UUID().uuidString, label: String, station: String, weekdaysOnly: Bool = false,
                address: String? = nil, coordinate: Coordinate? = nil) {
        self.id = id
        self.label = label
        self.station = station
        self.weekdaysOnly = weekdaysOnly
        self.address = address
        self.coordinate = coordinate
    }
}

/// Samma ruta som servern godtar: Stockholms län med lite marginal.
public func isInStockholm(_ point: Coordinate) -> Bool {
    (58.6...60.4).contains(point.lat) && (17.2...19.6).contains(point.lon)
}

/// Bara vardagar: appen föreslår inte destinationen på helgen, men du kan fortfarande välja den själv.
public func isAvailable(_ place: Place, now: Date, calendar: Calendar = .current) -> Bool {
    !place.weekdaysOnly || !calendar.isDateInWeekend(now)
}

/// När du är framme blir nästa destination aktiv, så Hem ger Jobbet och tvärtom.
/// Annars ligger valet kvar. `chosenId` är det du själv valt, det gäller tills du är framme.
public func nextDestination(_ places: [Place], activeId: String?, stationName: String, now: Date, chosenId: String? = nil) -> Place? {
    guard let active = places.first(where: { $0.id == activeId }) ?? places.first else { return nil }
    let open = { (place: Place) in isAvailable(place, now: now) }
    if active.station != stationName && (open(active) || active.id == chosenId) { return active }
    let index = places.firstIndex(of: active)!
    let others = Array(places[(index + 1)...] + places[..<index])
    return others.first { $0.station != stationName && open($0) }
        ?? ([active] + others).first { $0.station == stationName && open($0) }
        ?? active
}
