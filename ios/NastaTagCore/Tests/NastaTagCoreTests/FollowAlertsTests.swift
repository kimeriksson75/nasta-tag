import Foundation
import Testing
@testable import NastaTagCore

// Notiserna i Följ. Kims beslut: högst två medan du är kvar, inga när du går. Se ios/MUST_STAY.md.

private let start = Date(timeIntervalSince1970: 1_794_812_400)
private func minute(_ m: Double) -> Date { start.addingTimeInterval(m * 60) }
private let home = FollowSpot.stillHere(atPlace: true)

private func trip(_ key: String = "a", leave: Double, train: Double? = nil, now: Date = start) -> Trip {
    let slack = minute(leave).timeIntervalSince(now) / 60
    return Trip(key: key, leaveAt: minute(leave), time: minute(train ?? leave + 8), arrival: minute(leave + 40), mode: 2,
                line: "18", towards: "Farsta strand", stop: Stop(name: "Hökarängen", lat: 59.26, lon: 18.08),
                walkMinutes: 8, walkMeters: 600, transfers: [], slackMinutes: slack, status: classify(slack))
}

@Test func atMostTwoAlertsWhileStillHere() {
    var alerts = FollowAlerts()
    let plan = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(plan == [.soon: minute(15), .go: minute(18)])
    #expect(alerts.plan(trip(leave: 20), spot: home, now: start) == plan, "samma plan igen ger inga dubbletter")
    #expect(alerts.plan(trip(leave: 20, now: minute(16)), spot: home, now: minute(16)) == [.go: minute(18)])
    #expect(alerts.plan(trip(leave: 20, now: minute(19)), spot: home, now: minute(19)).isEmpty)
}

@Test func followingLateOnlyGivesWhatIsLeft() {
    var alerts = FollowAlerts()
    #expect(alerts.plan(trip(leave: 4), spot: home, now: start) == [.go: minute(2)])
    var late = FollowAlerts()
    #expect(late.plan(trip(leave: 1), spot: home, now: start).isEmpty)
}

@Test func newTimesMoveTheAlerts() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(alerts.plan(trip(leave: 26), spot: home, now: minute(1)) == [.soon: minute(21), .go: minute(24)])
    #expect(alerts.plan(trip(leave: 17), spot: home, now: minute(2)) == [.soon: minute(12), .go: minute(15)], "längre gångtid")
}

/// Blir tåget sent efter att notisen kommit, kommer den inte en gång till.
@Test func anAlertComesOncePerDeparture() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(alerts.plan(trip(leave: 30, now: minute(16)), spot: home, now: minute(16)) == [.go: minute(28)])
}

@Test func walkingIsSilent() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(alerts.plan(trip(leave: 20), spot: .walking, now: minute(2)).isEmpty)
    // Byter appen avgång på vägen är du fortfarande på väg.
    #expect(alerts.plan(trip("b", leave: 25), spot: .stillHere(atPlace: false), now: minute(3)).isEmpty)
    #expect(alerts.left)
    // Gick du tillbaka hem börjar notiserna om.
    #expect(alerts.plan(trip("b", leave: 25), spot: home, now: minute(4)) == [.soon: minute(20), .go: minute(23)])
}

@Test func atTheStopIsSilent() {
    var alerts = FollowAlerts()
    #expect(alerts.plan(trip(leave: 20), spot: .atStop, now: start).isEmpty)
    #expect(alerts.change(key: "a", trip: nil, lost: .cancelled, spot: .atStop, now: start) == nil)
}

/// Snooze och ångra flyttar notiserna till avgången som gäller.
@Test func snoozeMovesTheAlerts() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(alerts.plan(trip("b", leave: 30), spot: home, now: minute(16)) == [.soon: minute(25), .go: minute(28)])
    #expect(alerts.plan(trip(leave: 20, now: minute(17)), spot: home, now: minute(17)) == [.go: minute(18)])
}

@Test func missedAndLostCancel() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    #expect(alerts.plan(trip(leave: 20, now: minute(21)), spot: home, now: minute(21)).isEmpty)
}

// MARK: Undantaget

@Test func cancelledIsToldOnceEvenWhenWalking() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: .walking, now: start)
    #expect(alerts.change(key: "a", trip: nil, lost: .cancelled, spot: .walking, now: minute(1)) == .cancelled)
    #expect(alerts.change(key: "a", trip: nil, lost: .cancelled, spot: .walking, now: minute(2)) == nil)
}

@Test func earlierDepartureIsTold() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 10, train: 18), spot: .walking, now: start)
    let moved = trip(leave: 7, train: 15, now: minute(8))
    #expect(alerts.change(key: "a", trip: moved, lost: nil, spot: .walking, now: minute(8)) == .earlier)
}

/// Att du själv gick för sent, eller att svaren saknar avgången, är ingen ändring.
@Test func beingLateIsNotAChange() {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 10), spot: .walking, now: start)
    #expect(alerts.change(key: "a", trip: trip(leave: 10, now: minute(11)), lost: nil, spot: .walking, now: minute(11)) == nil)
    #expect(alerts.change(key: "a", trip: trip(leave: 7, train: 15, now: minute(11)), lost: nil, spot: .walking, now: minute(11)) == nil)
    #expect(alerts.change(key: "a", trip: nil, lost: nil, spot: .walking, now: minute(11)) == nil)
}

@Test func memorySurvivesARestart() throws {
    var alerts = FollowAlerts()
    _ = alerts.plan(trip(leave: 20), spot: home, now: start)
    var again = try JSONDecoder().decode(FollowAlerts.self, from: JSONEncoder().encode(alerts))
    #expect(again == alerts)
    #expect(again.plan(trip(leave: 30, now: minute(16)), spot: home, now: minute(16)) == [.go: minute(28)])
}

// MARK: SL:s svar

private func journey(status: String? = nil, secondDep: String? = nil, secondStatus: String? = nil) throws -> Journey {
    func leg(_ id: String, _ dep: String, _ arr: String, _ status: String?) -> [String: Any] {
        ["transportation": ["id": id, "product": ["class": 2]], "realtimeStatus": status.map { [$0] } ?? [],
         "origin": ["coord": [59.3, 18.0], "departureTimePlanned": "2026-11-17T\(dep):00Z"],
         "destination": ["arrivalTimePlanned": "2026-11-17T\(arr):00Z"]]
    }
    var legs = [leg("x", "10:00", "10:20", status)]
    if let secondDep { legs.append(leg("y", secondDep, "10:50", secondStatus)) }
    return try JSONDecoder().decode(Journey.self, from: JSONSerialization.data(withJSONObject: ["legs": legs]))
}

@Test func changeIsReadFromTheAnswers() throws {
    let key = "x|2026-11-17T10:00:00Z"
    #expect(followChange([try journey()], key: key) == nil)
    #expect(followChange([], key: key) == nil, "saknas i svaret är inte inställd")
    #expect(followChange([try journey(status: "TRIP_CANCELLED")], key: key) == .cancelled)
    #expect(followChange([try journey(secondDep: "10:10")], key: key) == .connectionLost)
    #expect(followChange([try journey(secondDep: "10:30", secondStatus: "TRIP_CANCELLED")], key: key) == .connectionLost)
    #expect(followChange([try journey(secondDep: "10:10"), try journey(secondDep: "10:30")], key: key) == nil, "ett annat byte går")
    #expect(followChange([try journey(status: "TRIP_CANCELLED")], key: "annan") == nil)
}

@Test func alertsSpeakLikeTheCard() {
    let soon = followAlertWords(.soon, trainTime: start, mode: 2, label: "Hem")
    #expect(soon.title == departureMessage(status: .hurry, minutes: 5, trainTime: start, label: "Hem").title)
    #expect(soon.body.contains("5 min") && soon.body.contains("-tåget hem"))
    let go = followAlertWords(.go, trainTime: start, mode: 2, label: "Hem")
    #expect(go.body.contains("-tåget hem") && !go.body.contains("{"))
    let change = followChangeWords(.cancelled, trainTime: start, mode: 5, label: "Jobbet", next: trip("b", leave: 20))
    #expect(change.title == "Inställt." && change.body.contains("-bussen till jobbet") && change.body.hasSuffix("i stället."))
}
