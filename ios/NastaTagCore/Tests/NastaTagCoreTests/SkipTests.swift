import Foundation
import NastaTagCore
import Testing

private let times = (0..<480).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 180) }

@Test func skipWordsFitAndAgree() {
    for time in times {
        for label in ["Jobbet", "Hem", "Gymmet"] {
            for mode in [0, 2, 5] {
                let words = skipWords(label: label, trainTime: time, mode: mode)
                // Knappen är 180 punkter bred, och "Jobbet klarar sig." tar 147.
                #expect(words.button.count <= 18, "\(words.button)")
                #expect(words.button.hasSuffix("."), "\(words.button)")
                #expect(words.ask.hasSuffix("?"), "\(words.ask)")
                #expect(!Voice.sharesWord(words.button, words.ask), "\(words.button) / \(words.ask)")
                #expect(words.done.hasSuffix(".") && !words.done.contains("{"), "\(words.done)")
                #expect(!Voice.sharesWord(words.button, words.done), "\(words.button) / \(words.done)")
                // Alltid idag och imorgon, i ett ord.
                let all = "\(words.button) \(words.ask) \(words.detail) \(words.done)".lowercased()
                #expect(!all.contains("i dag") && !all.contains("i morgon"), "\(all)")
                if label != "Jobbet" { #expect(words.done != "Ibland vinner soffan.") }
                #expect(words.detail.hasPrefix("Vi slutar påminna dig om ") && words.detail.contains(Mode(mode).noun))
            }
        }
    }
}

@Test func skipWordsFollowTheDestination() {
    let work = Set(times.map { skipWords(label: "Jobbet", trainTime: $0, mode: 2).button })
    let home = Set(times.map { skipWords(label: "Hem", trainTime: $0, mode: 2).button })
    let other = Set(times.map { skipWords(label: "Gymmet", trainTime: $0, mode: 2).button })
    #expect(work.contains("Sängen vinner.") && !home.contains("Sängen vinner.") && !other.contains("Sängen vinner."))
    #expect(home.contains("En öl till.") && !work.contains("En öl till."))
    #expect(other.contains("Inte idag."))
    #expect(work.contains("Fuck it.") && home.contains("Skit i det."))
    #expect(!Set(times.map { skipWords(label: "Hem", trainTime: $0, mode: 2).ask }).contains("Ledig idag?"))
    #expect(skipWords(label: "Hem", trainTime: times[0], mode: 5).detail == "Vi slutar påminna dig om bussen idag.")
}

@Test func dayIsStockholmDay() {
    // 23:30 i Stockholm är fortfarande samma dag, fast det är en annan dag i UTC-tid efter midnatt.
    let late = ISO8601DateFormatter().date(from: "2026-11-15T22:30:00Z")!
    #expect(stockholmDay(late) == "2026-11-15")
    #expect(stockholmDay(late.addingTimeInterval(3600)) == "2026-11-16")
}
