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

@Test func trainsMustPassTheTarget() {
    #expect(metro.trainReaches(from: "Gubbängen", destination: "Alvik", target: "T-Centralen"))
    #expect(!metro.trainReaches(from: "Gubbängen", destination: "Hagsätra", target: "T-Centralen"))
}

@Test func transferWhenLinesDiffer() {
    let plan = metro.planTrip(from: "Gubbängen", to: "Tekniska högskolan")
    #expect(plan.transfer != nil)
    #expect(metro.planTrip(from: "Gubbängen", to: "Slussen").transfer == nil)
}

@Test func boardFromSlDepartures() throws {
    let json = """
    [{"destination":"Alvik","state":"EXPECTED","scheduled":"2026-11-11T16:20:00","expected":"2026-11-11T16:21:00","line":{"designation":"18"},"journey":{"id":1}},
     {"destination":"Alvik","state":"CANCELLED","scheduled":"2026-11-11T16:25:00","line":{"designation":"18"},"journey":{"id":2}},
     {"destination":"Hagsätra","scheduled":"2026-11-11T16:22:00","line":{"designation":"19"},"journey":{"id":3}}]
    """
    let departures = try JSONDecoder().decode([Departure].self, from: Data(json.utf8))
    let now = stockholmDate("2026-11-11T16:10:00")!
    let board = buildBoard(departures: departures, metro: metro, from: "Gubbängen", target: "T-Centralen", now: now, walkMinutes: 8)
    #expect(board.count == 1)
    #expect(board[0].status == .hurry)
    #expect(departureMessage(board[0]).wait == "3 min")
}

@Test func homeGivesWork() {
    let home = Place(id: "h", label: "Hem", station: "Gubbängen")
    let work = Place(id: "w", label: "Jobbet", station: "T-Centralen", weekdaysOnly: true)
    let wednesday = stockholmDate("2026-11-11T08:00:00")!
    let saturday = stockholmDate("2026-11-14T08:00:00")!
    #expect(nextDestination([home, work], activeId: "h", stationName: "Gubbängen", now: wednesday)?.id == "w")
    #expect(nextDestination([home, work], activeId: "h", stationName: "Gubbängen", now: saturday)?.id == "h")
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
}
