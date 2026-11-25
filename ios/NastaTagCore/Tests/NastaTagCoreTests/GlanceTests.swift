import Foundation
import Testing
@testable import NastaTagCore

// Widgeten får aldrig visa något appen inte skulle säga, och aldrig gamla tider som om de vore färska.

private func fixture() throws -> (journeys: [Journey], now: Date) {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    let journeys = try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
    let first = try #require(buildTrips(journeys, now: .distantPast).first)
    return (journeys, first.leaveAt.addingTimeInterval(-7 * 60 - 20))
}

@Test func glanceSaysTheSameAsTheApp() throws {
    let (journeys, now) = try fixture()
    let moments = glanceTimeline(journeys, fetchedAt: now, positionAt: now)
    #expect(moments.count > 2)
    for moment in moments {
        guard case .countdown(let trip) = moment.glance else { continue }
        #expect(trip == pickTrips(buildTrips(journeys, now: moment.date)).next)
        #expect(trip.leaveAt >= moment.date, "aldrig en avgång du inte hinner")
    }
}

/// Minuterna på skärmen är rätt hela tiden fram till nästa ögonblick, inte bara när det börjar.
@Test func glanceMinutesNeverLag() throws {
    let (journeys, now) = try fixture()
    let moments = glanceTimeline(journeys, fetchedAt: now, positionAt: now)
    for (moment, after) in zip(moments, moments.dropFirst()) {
        #expect(moment.date < after.date)
        guard case .countdown(let trip) = moment.glance else { continue }
        let justBefore = trip.leaveAt.timeIntervalSince(after.date.addingTimeInterval(-1)) / 60
        #expect(minutesToLeave(trip.slackMinutes) == minutesToLeave(justBefore))
        #expect(classify(justBefore) == trip.status, "färgen byts på samma gräns som i appen")
    }
}

@Test func glanceGoesStale() throws {
    let (journeys, now) = try fixture()
    let last = try #require(glanceTimeline(journeys, fetchedAt: now, positionAt: now).last)
    #expect(last.glance == .stale)
    #expect(last.date <= now.addingTimeInterval(glanceFreshSeconds))
}

/// Vet widgeten inte var du är säger den aldrig när du ska gå.
@Test func glanceWithOldPositionShowsTheClock() throws {
    let (journeys, now) = try fixture()
    for moment in glanceTimeline(journeys, fetchedAt: now, positionAt: now.addingTimeInterval(-glancePositionSeconds)) {
        if case .countdown = moment.glance { Issue.record("nedräkning från gammal plats") }
    }
    for moment in glanceTimeline(journeys, fetchedAt: now, positionAt: now)
    where moment.date >= now.addingTimeInterval(glancePositionSeconds) {
        if case .countdown = moment.glance { Issue.record("positionen hinner bli gammal") }
    }
}

@Test func glanceKeepsTheSnooze() throws {
    let (journeys, now) = try fixture()
    let first = try #require(pickTrips(buildTrips(journeys, now: now)).next)
    for moment in glanceTimeline(journeys, fetchedAt: now, positionAt: now, snoozedLeaveAt: first.leaveAt) {
        if case .countdown(let trip) = moment.glance { #expect(trip.leaveAt > first.leaveAt) }
    }
}

@Test func glanceWithoutTripsHasWords() {
    let moments = glanceTimeline([], fetchedAt: .now, positionAt: .now)
    #expect(moments.count == 1)
    guard case .words = moments[0].glance else { Issue.record("tom widget"); return }
}

/// Platserna överlever vägen till widgeten.
@Test func sharedStateKeepsThePlaces() throws {
    let state = SharedState(places: [Place(label: "Hem", weekdaysOnly: true, address: "Gatan 1", coordinate: Coordinate(lat: 59.3, lon: 18))],
                            activeId: "a", skippedDay: "a|2026-11-25", snoozedLeaveAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(try JSONDecoder().decode(SharedState.self, from: JSONEncoder().encode(state)) == state)
}
