import Foundation
import Testing
@testable import NastaTagCore

/// 1794931200 är en tisdag 17:00 i Stockholm.
private let evening = Date(timeIntervalSince1970: 1_794_931_200)

private func trip(_ time: Date, mode: Int = 2, transfers: [String] = []) -> Trip {
    Trip(key: "a", leaveAt: time, time: time, arrival: time.addingTimeInterval(29 * 60), mode: mode, line: "18", towards: "Farsta strand",
         stop: Stop(name: "Hötorget", lat: 59.33, lon: 18.06), walkMinutes: 0, walkMeters: 0, transfers: transfers)
}

@Test func tellAlwaysSaysTheArrivalAndNothingPrivate() {
    for label in ["Hem", "Jobbet", "Gymmet"] {
        for mode in [0, 2, 4, 5, 9, -1] {
            for minutes in stride(from: 0, to: 24 * 60, by: 7) {
                let trip = trip(evening.addingTimeInterval(Double(minutes) * 60), mode: mode)
                let words = tellWords(trip, label: label)
                #expect(words.message.contains(stockholmClock(trip.arrival)))
                #expect(!words.message.contains("{") && !words.message.contains("Hötorget") && !words.message.contains("http"))
                #expect(words == tellWords(trip, label: label), "samma resa, samma ord")
            }
        }
    }
}

@Test func tellFitsThePlaceAndTheHour() {
    #expect(tellWords(trip(evening), label: "Hem").button == "Säg till hemma")
    #expect(tellWords(trip(evening), label: "Jobbet").button == "Säg till jobbet")
    #expect(tellWords(trip(evening), label: "Gymmet").button == "Säg till")
    #expect(tellWords(trip(evening), label: "Hem").message.contains("Hemma 17:29"))
    #expect(tellWords(trip(evening), label: "Jobbet").message.contains("Inne 17:29"))
    #expect(tellWords(trip(evening, mode: 5), label: "Hem").message.contains("bussen"))
    for minutes in 0..<60 {
        let late = tellWords(trip(evening.addingTimeInterval(Double(300 + minutes) * 60)), label: "Hem").message
        #expect(Voice.tellHomeLate.contains { late.hasSuffix($0.components(separatedBy: "{t}").last!) })
    }
}

@Test func tellPromisesLessWithATransfer() {
    #expect(tellWords(trip(evening, transfers: ["Slussen"]), label: "Hem").message.contains("Hemma runt 17:29"))
}

@Test func tellVaries() {
    let seen = Set((0..<400).map { tellWords(trip(evening.addingTimeInterval(Double($0) * 60)), label: "Gymmet").message.prefix(8) })
    #expect(seen.count == Voice.tellOther.count)
}
