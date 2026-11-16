import Foundation
import Testing
@testable import NastaTagCore

private func trips(now: (Trip) -> Date) throws -> (trips: [Trip], now: Date, first: Trip) {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    let all = try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
    let first = try #require(parseJourney(all[0]))
    let at = now(first)
    return (buildTrips(all, now: at), at, first)
}

/// En punkt så här många meter norr om hållplatsen.
private func north(of stop: Stop, _ meters: Double) -> Coordinate {
    Coordinate(lat: stop.lat + meters / 111_195, lon: stop.lon)
}

@Test func framIsGenerousAtBigStations() {
    let stop = Stop(name: "T-Centralen", lat: 59.331, lon: 18.059)
    #expect(isAtStop(north(of: stop, 40), stop), "på perrongen, 40 m från hållplatsens mitt")
    #expect(isAtStop(north(of: stop, 70), stop))
    #expect(!isAtStop(north(of: stop, 90), stop))
    #expect(isAtStop(north(of: stop, 90), stop, accuracy: 95), "osäker GPS under jord")
    #expect(!isAtStop(north(of: stop, 140), stop, accuracy: 400), "men aldrig mer än 100 m")
}

@Test func walkLeftShrinksAsYouWalk() {
    let stop = Stop(name: "T-Centralen", lat: 59.331, lon: 18.059)
    let from = north(of: stop, 400)
    // SL:s gångväg från där resan hämtades är längre än fågelvägen.
    #expect(abs(walkLeft(position: from, stop: stop, walkMeters: 520, fetchedFrom: from) - 520) < 1)
    #expect(abs(walkLeft(position: north(of: stop, 200), stop: stop, walkMeters: 520, fetchedFrom: from) - 260) < 1)
    #expect(abs(walkLeft(position: north(of: stop, 40), stop: stop, walkMeters: 520, fetchedFrom: from) - 52) < 1)
    // Utan gångväg från SL, eller med en orimlig, blir det fågelvägen eller högst dubbla den.
    #expect(abs(walkLeft(position: from, stop: stop, walkMeters: 0, fetchedFrom: from) - 400) < 1)
    #expect(abs(walkLeft(position: from, stop: stop, walkMeters: 5000, fetchedFrom: from) - 800) < 1)
}

@Test func atTheStopTheTrainIsLockedAndCalm() throws {
    // Du kommer fram när du egentligen skulle ha gått: resan är missad om man räknar gångvägen.
    let (all, now, first) = try trips { $0.leaveAt.addingTimeInterval(60) }
    #expect(all.first { $0.key == first.key }?.status == .missed)
    let trip = try #require(tripAtStop(all, position: north(of: first.stop, 30), now: now))
    #expect(trip.time > now)
    #expect(trip.status == .calm, "framme i tid är lugnt, även med en minut kvar")
    #expect(trip.walkMinutes == 0 && trip.leaveAt == trip.time)
    #expect(tripAtStop(all, position: north(of: first.stop, 500), now: now) == nil, "inte framme")
}

@Test func theTrainLeavesWithYou() throws {
    let (_, now, first) = try trips { $0.time.addingTimeInterval(-3 * 60) }
    let trip = arrivedTrip(first, now: now)
    let platform = north(of: trip.stop, 30)
    #expect(stopOutcome(trip, position: platform, now: now) == .waiting)
    #expect(stopOutcome(trip, position: platform, now: trip.time) == .boarded, "tåget gick medan du stod där")
    #expect(stopOutcome(trip, position: north(of: trip.stop, 600), now: now) == .left, "du gick därifrån")
    #expect(stopOutcome(trip, position: north(of: trip.stop, 600), now: trip.time.addingTimeInterval(-30)) == .boarded,
            "tåget gick lite tidigt, med dig")
    #expect(stopOutcome(trip, position: nil, now: now) == .waiting)
}

@Test func arrivedWordsRead() {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let message = arrivedMessage(minutes: minutesToDeparture(3.2), trainTime: time)
    #expect(message.wait == "4 min", "räknar uppåt medan du väntar")
    #expect(Voice.arrivedHeadlines.contains(message.headline))
    #expect(!Voice.sharesWord(message.headline, message.caption))
    #expect(arrivedMessage(minutes: minutesToDeparture(0.4), trainTime: time).wait == "Strax")
    for line in Voice.arrivedHeadlines {
        #expect(line.count <= 16 && line.hasSuffix("."), "ryms bredvid minuterna på låsskärmen: \(line)")
    }
    for line in Voice.boardedHeadlines {
        #expect(line.count <= 29 && line.hasSuffix("."), "\(line)")
    }
    #expect(Voice.boardedHeadlines.contains(boardedHeadline(trainTime: time)))
}
