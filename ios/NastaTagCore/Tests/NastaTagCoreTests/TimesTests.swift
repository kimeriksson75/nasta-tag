import Foundation
import Testing
@testable import NastaTagCore

// Tiderna som visas: när du ska gå, när fordonet går och när du är framme. Resorna byggs som SL
// skickar dem, med tidtabell och prognos för varje ben, så att förseningar och byten kan provas.

/// Klockslag i Stockholm den 17 november 2026 (vintertid, UTC+1).
private func at(_ clock: String) -> Date {
    ISO8601DateFormatter().date(from: "2026-11-17T\(clock):00+01:00")!
}

private func iso(_ clock: String?) -> String? {
    clock.map { ISO8601DateFormatter().string(from: at($0)) }
}

/// Ett ben i resan. Prognosen saknas när fordonet går enligt tidtabellen.
private struct Leg {
    var kind: Int // 99 gång, 2 tunnelbana, 5 buss
    var from: String, dep: String, depLate: String? = nil
    var to: String, arr: String, arrLate: String? = nil
    var line = "18"

    static func walk(_ from: String, _ dep: String, _ to: String, _ arr: String) -> Leg {
        Leg(kind: 99, from: from, dep: dep, to: to, arr: arr)
    }
    static func metro(_ from: String, _ dep: String, _ to: String, _ arr: String, late: Int = 0) -> Leg {
        Leg(kind: 2, from: from, dep: dep, depLate: late > 0 ? shifted(dep, late) : nil,
            to: to, arr: arr, arrLate: late > 0 ? shifted(arr, late) : nil)
    }
    static func bus(_ from: String, _ dep: String, _ to: String, _ arr: String) -> Leg {
        Leg(kind: 5, from: from, dep: dep, to: to, arr: arr, line: "26")
    }

    private static func shifted(_ clock: String, _ minutes: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Stockholm")
        return f.string(from: at(clock).addingTimeInterval(Double(minutes) * 60))
    }

    var json: [String: Any] {
        func point(_ name: String, _ times: [String: String?]) -> [String: Any] {
            var point: [String: Any] = ["name": name, "coord": [59.33, 18.06]]
            for (key, value) in times { if let value { point[key] = value } }
            return point
        }
        var transportation: [String: Any] = ["product": ["class": kind]]
        if kind != 99 {
            transportation["id"] = "\(kind)-\(line)-\(dep)"
            transportation["disassembledName"] = line
            transportation["destination"] = ["name": "Farsta strand"]
        }
        return [
            "transportation": transportation,
            "origin": point(from, ["departureTimePlanned": iso(dep), "departureTimeEstimated": iso(depLate)]),
            "destination": point(to, ["arrivalTimePlanned": iso(arr), "arrivalTimeEstimated": iso(arrLate)]),
        ]
    }
}

private func trip(_ legs: [Leg]) throws -> Trip? {
    let data = try JSONSerialization.data(withJSONObject: ["journeys": [["legs": legs.map(\.json)]]])
    let journey = try #require(try JSONDecoder().decode(JourneysResponse.self, from: data).journeys?.first)
    return parseJourney(journey)
}

// MARK: Gå, avgå, framme

@Test func onTimeTripKeepsTheTimetable() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "15:01", "T-Centralen", "15:11"),
        .metro("T-Centralen", "15:11", "Gubbängen", "15:29"),
        .walk("Gubbängen", "15:29", "Knektvägen", "15:33"),
    ]))
    #expect(trip.leaveAt == at("15:01"))
    #expect(trip.time == at("15:11"))
    #expect(trip.arrival == at("15:33"))
    #expect(trip.walkMinutes == 10)
}

/// Signalfel: tåget går 32 minuter sent. Du ska gå tio minuter före det sena tåget och är framme
/// när det sena tåget har kommit fram och du gått hem, även om SL har kvar gångens gamla tider.
@Test func lateTrainMovesLeavingAndArriving() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "15:01", "T-Centralen", "15:11"),
        .metro("T-Centralen", "15:11", "Gubbängen", "15:29", late: 32),
        .walk("Gubbängen", "15:29", "Knektvägen", "15:33"),
    ]))
    #expect(trip.time == at("15:43"))
    #expect(trip.leaveAt == at("15:33"))
    #expect(trip.arrival == at("16:05"))
    #expect(trip.walkMinutes == 10)
}

/// Tåget är så sent att bussen du skulle byta till redan har gått. Den resan går inte att göra,
/// och med den kvar blev du "hemma" före avgången.
@Test func missedConnectionIsNotShown() throws {
    #expect(try trip([
        .walk("Hemma", "15:11", "Hötorget", "15:17"),
        .metro("Hötorget", "15:20", "Slussen", "15:25", late: 24),
        .walk("Slussen", "15:26", "Glasbruksgatan", "15:36"),
        .bus("Glasbruksgatan", "15:36", "Nacka", "15:46"),
    ]) == nil)
}

/// Lite sent gör inget så länge bytet hinns: då gäller bussens tid.
@Test func connectionThatStillHoldsIsShown() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "15:11", "Hötorget", "15:17"),
        .metro("Hötorget", "15:20", "Slussen", "15:25", late: 2),
        .walk("Slussen", "15:27", "Glasbruksgatan", "15:33"),
        .bus("Glasbruksgatan", "15:36", "Nacka", "15:46"),
        .walk("Nacka", "15:46", "Vikdalsvägen", "15:51"),
    ]))
    #expect(trip.time == at("15:22"))
    #expect(trip.arrival == at("15:51"))
    #expect(trip.transfers == ["Glasbruksgatan"])
}

/// Går tåget en minut tidigt är resan fortfarande giltig, du får gå en minut tidigare.
@Test func earlyTrainIsStillShown() throws {
    var early = Leg.metro("T-Centralen", "15:11", "Gubbängen", "15:29")
    early.depLate = "15:10"
    let trip = try #require(try trip([.walk("Hemma", "15:01", "T-Centralen", "15:11"), early]))
    #expect(trip.leaveAt == at("15:00"))
}

/// Det som alltid måste stämma, för varje resa SL kan skicka: gå före avgång, avgång före framme.
@Test func timesAlwaysComeInOrder() throws {
    let url = Bundle.module.url(forResource: "trips", withExtension: "json")!
    let journeys = try JSONDecoder().decode(JourneysResponse.self, from: Data(contentsOf: url)).journeys ?? []
    let cases: [[Leg]] = [
        [.walk("A", "15:01", "B", "15:11"), .metro("B", "15:11", "C", "15:29", late: 45), .walk("C", "15:29", "D", "15:33")],
        [.metro("B", "15:11", "C", "15:29", late: 5)],
        [.walk("A", "15:01", "B", "15:11"), .metro("B", "15:11", "C", "15:20", late: 3), .bus("C", "15:30", "D", "15:40")],
    ]
    let trips = journeys.compactMap(parseJourney) + (try cases.compactMap { try trip($0) })
    #expect(trips.count >= journeys.count)
    for trip in trips {
        #expect(trip.leaveAt <= trip.time, "\(trip.key): gå efter avgång")
        #expect(trip.time < trip.arrival, "\(trip.key): framme före avgång")
        #expect(trip.walkMinutes >= 0)
    }
}

// MARK: Orden

@Test func lineUnderTheTripReads() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "14:32", "T-Centralen", "14:42"),
        .metro("T-Centralen", "14:42", "Gubbängen", "14:47"),
        .walk("Gubbängen", "14:47", "Knektvägen", "14:51"),
    ]))
    #expect(tripLine(trip, label: "Hem", atStop: false) == "Linje 18 från T-Centralen · hemma 14:51")
    // Vid perrongen behövs riktningen.
    #expect(tripLine(trip, label: "Hem", atStop: true) == "Linje 18 mot Farsta strand från T-Centralen · hemma 14:51")
    #expect(tripLine(trip, label: "Jobbet", atStop: false).hasSuffix("· på jobbet 14:51"))
    #expect(tripLine(trip, label: "Gymmet", atStop: false).hasSuffix("· framme 14:51"))
}

@Test func lineNamesTheTransfers() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "15:11", "Hötorget", "15:17"),
        .metro("Hötorget", "15:20", "Slussen", "15:25"),
        .walk("Slussen", "15:27", "Glasbruksgatan", "15:33"),
        .bus("Glasbruksgatan", "15:36", "Nacka", "15:46"),
    ]))
    #expect(tripLine(trip, label: nil, atStop: false) == "Linje 18 från Hötorget · byte Glasbruksgatan · framme 15:46")
}

/// Ankomsten och avgången på samma kort får aldrig säga emot varandra.
@Test func arrivalNeverReadsBeforeTheTrain() throws {
    let trip = try #require(try trip([
        .walk("Hemma", "15:01", "T-Centralen", "15:11"),
        .metro("T-Centralen", "15:11", "Gubbängen", "15:29", late: 32),
        .walk("Gubbängen", "15:29", "Knektvägen", "15:33"),
    ]))
    #expect(tripName(trip, "Hem") == "15:43-tåget hem")
    #expect(arrivalPhrase("Hem", arrival: trip.arrival) == "hemma 16:05")
}
