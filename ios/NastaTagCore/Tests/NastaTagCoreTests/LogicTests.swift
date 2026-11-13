import Foundation
import Testing
@testable import NastaTagCore

private let metro = Metro.stockholm

@Test func distanceAndText() {
    let a = Coordinate(lat: 59.3, lon: 18), b = Coordinate(lat: 59.31, lon: 18)
    #expect(abs(distanceMeters(a, b) - 1112) < 2)
    #expect(abs(bearingDegrees(a, b)) < 0.01)
    #expect(distanceText(626) == "630 m")
    #expect(distanceText(1530) == "1,5 km")
}

@Test func marginColours() {
    #expect(classify(-0.1) == .missed)
    #expect(classify(1.9) == .rush)
    #expect(classify(4.9) == .hurry)
    #expect(classify(5) == .calm)
}

/// En riktig resa från SL: T-Centralen till Götgatan 100, med gång, tunnelbana och gång.
private func journeys() throws -> [Journey] {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    return try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
}

@Test func tripFromSlJourney() throws {
    let trip = try #require(parseJourney(try journeys()[0]))
    #expect(trip.mode == 2)
    #expect(trip.line == "17")
    #expect(trip.towards == "Skarpnäck")
    #expect(trip.stop.name == "T-Centralen")
    #expect(trip.lineText == "Linje 17 mot Skarpnäck")
    #expect(trip.walkMeters == 110)
    #expect(trip.walkMinutes > 0 && trip.walkMinutes < 10)
    #expect(trip.transfers.isEmpty)
    #expect(tripName(trip, "Hem").hasSuffix("-tåget hem"))
}

@Test func tripsGetMarginAndOrder() throws {
    let all = try journeys()
    let first = try #require(parseJourney(all[0]))
    let trips = buildTrips(all + all, now: first.leaveAt.addingTimeInterval(-6 * 60))
    #expect(trips.count == Set(trips.map(\.key)).count)
    #expect(trips.first?.status == .calm)
    #expect(zip(trips, trips.dropFirst()).allSatisfy { $0.leaveAt <= $1.leaveAt })
    let picked = pickTrips(trips)
    #expect(picked.next != nil)
    #expect(picked.later.count == trips.count - 1)
}

@Test func busIsNamedBus() {
    #expect(Mode(5).noun == "bussen")
    #expect(Mode(0).line == "Pendeltåg")
    #expect(Mode(42).noun == "avgången")
}

@Test func homeGivesWork() {
    let home = Place(id: "h", label: "Hem", coordinate: Coordinate(lat: 59.2627, lon: 18.0819))
    let work = Place(id: "w", label: "Jobbet", weekdaysOnly: true, coordinate: Coordinate(lat: 59.3313, lon: 18.0597))
    let wednesday = ISO8601DateFormatter().date(from: "2026-11-11T07:00:00Z")!
    let saturday = ISO8601DateFormatter().date(from: "2026-11-14T07:00:00Z")!
    #expect(nextDestination([home, work], activeId: "h", hereId: placeAt([home, work], position: Coordinate(lat: 59.2630, lon: 18.0820)), now: wednesday)?.id == "w")
    #expect(nextDestination([home, work], activeId: "h", hereId: placeAt([home, work], position: Coordinate(lat: 59.2630, lon: 18.0820)), now: saturday)?.id == "h")
    #expect(tripPhrase("Jobbet") == "till jobbet")
}

@Test func stockholmBox() {
    #expect(isInStockholm(Coordinate(lat: 59.33, lon: 18.06)))
    #expect(!isInStockholm(Coordinate(lat: 57.70, lon: 11.97))) // Göteborg
}

@Test func oldPlacesStillDecode() throws {
    let json = #"[{"id":"h","label":"Hem","station":"Gubbängen","weekdaysOnly":false}]"#
    let places = try JSONDecoder().decode([Place].self, from: Data(json.utf8))
    #expect(places[0].station == "Gubbängen")
    #expect(places[0].address == nil)
    let migrated = migratePlaces(places, metro: metro)
    #expect(migrated[0].coordinate != nil)
    #expect(placeAt(migrated, position: migrated[0].coordinate!) == "h")
}

@Test func messagesNeverContradict() {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let calm = departureMessage(status: .calm, minutes: 8, trainTime: time)
    #expect(calm.wait == "8 min")
    #expect(calm.caption == "tills du ska gå")
    let rush = departureMessage(status: .rush, minutes: 1, trainTime: time)
    #expect(rush.wait == "Gå nu")
    for status in [Status.calm, .hurry, .rush] {
        let headline = departureMessage(status: status, minutes: 3, trainTime: time).headline
        #expect(!headline.contains("gå") && !headline.contains("min"))
    }
    #expect(minutesToLeave(4.9) == 4)
    #expect(minutesToLeave(-0.2) == 0)
}
