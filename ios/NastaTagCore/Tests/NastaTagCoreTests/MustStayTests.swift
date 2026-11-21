import Foundation
import Testing
@testable import NastaTagCore

// Det som inte får försvinna. Varje test här vaktar en knapp eller ett beteende som användarna
// litar på. Går ett av dem sönder är det ett fel i appen, inte i testet: ändra inte testet för att
// få bygget grönt, utan bara när en sådan förändring är bestämd med Kim. Se ios/MUST_STAY.md.

private func fixture(now: (Trip) -> Date) throws -> (trips: [Trip], now: Date) {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    let journeys = try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
    let first = try #require(parseJourney(journeys[0]))
    let at = now(first)
    return (buildTrips(journeys, now: at), at)
}

private func north(of point: Coordinate, _ meters: Double) -> Coordinate {
    Coordinate(lat: point.lat + meters / 111_195, lon: point.lon)
}

private func coordinate(_ stop: Stop) -> Coordinate { stop.coordinate }

// MARK: Snooze

/// Finns det en senare avgång att byta till ska Snooze synas, med hur mycket senare du kan gå.
@Test func snoozeIsThereWhenThereIsALaterDeparture() throws {
    let (trips, now) = try fixture { $0.leaveAt.addingTimeInterval(-10 * 60) }
    let next = try #require(pickTrips(trips).next)
    let later = try #require(snoozeTarget(after: next, in: trips))
    let button = snoozeButton(next: next, trips: trips, atStop: false, snoozed: nil, now: now)
    guard case .snooze(let minutes) = button else { Issue.record("Snooze saknas: \(button)"); return }
    #expect(minutes >= 1)
    #expect(later.leaveAt > next.leaveAt)
}

/// Efter ett tryck blir knappen Ångra snooze, och den går att trycka på tills avgången du hoppade över går.
@Test func snoozeTurnsIntoUndo() throws {
    let (trips, now) = try fixture { $0.leaveAt.addingTimeInterval(-10 * 60) }
    let skipped = try #require(pickTrips(trips).next)
    let after = try #require(snoozeTarget(after: skipped, in: trips))
    #expect(snoozeButton(next: after, trips: trips, atStop: false, snoozed: skipped, now: now) == .undo(enabled: true))
    #expect(snoozeButton(next: after, trips: trips, atStop: false, snoozed: skipped,
                         now: skipped.leaveAt.addingTimeInterval(1)) == .undo(enabled: false))
}

/// Knappen försvinner bara av två skäl: du står vid hållplatsen, eller det finns ingen senare avgång.
@Test func snoozeOnlyGoesAwayForAReason() throws {
    let (trips, now) = try fixture { $0.leaveAt.addingTimeInterval(-10 * 60) }
    let next = try #require(pickTrips(trips).next)
    #expect(snoozeButton(next: next, trips: trips, atStop: true, snoozed: nil, now: now) == .none, "vid hållplatsen")
    #expect(snoozeButton(next: next, trips: [next], atStop: false, snoozed: nil, now: now) == .none, "ingen senare avgång")
}

// MARK: Hemma är inte vid hållplatsen

/// Bor du granne med en busshållplats står du hemma, inte vid bussen. Annars låste appen bussen
/// utanför porten i stället för den snabbaste resan, och Snooze försvann.
@Test func homeNextToABusStopIsHome() throws {
    let (trips, now) = try fixture { $0.leaveAt.addingTimeInterval(-10 * 60) }
    let stop = try #require(trips.first).stop
    let home = north(of: coordinate(stop), 60)
    // Inne i huset, med lite osäker GPS.
    for position in [home, north(of: home, -15), north(of: home, 10)] {
        #expect(tripAtStop(trips, position: position, accuracy: 65, now: now, place: home) == nil)
    }
    // Ute vid hållplatsen är du framme, även nära hemmet.
    #expect(tripAtStop(trips, position: north(of: coordinate(stop), 5), now: now, place: home) != nil)
}

/// Långt från dina platser fungerar framme vid hållplatsen som förut.
@Test func awayFromHomeTheStopStillLocks() throws {
    let (trips, now) = try fixture { $0.leaveAt.addingTimeInterval(-10 * 60) }
    let stop = try #require(trips.first).stop
    #expect(tripAtStop(trips, position: north(of: coordinate(stop), 30), now: now) != nil)
}

// MARK: Strunta i resan

/// "Strunta i resan idag" har alltid ord att visa när det finns en resa.
@Test func skipAlwaysHasWords() throws {
    let (trips, _) = try fixture { $0.leaveAt }
    for trip in trips {
        for label in ["Hem", "Jobbet", "Gymmet"] {
            let words = skipWords(label: label, trainTime: trip.time, mode: trip.mode)
            #expect(!words.button.isEmpty && !words.ask.isEmpty)
        }
    }
}
