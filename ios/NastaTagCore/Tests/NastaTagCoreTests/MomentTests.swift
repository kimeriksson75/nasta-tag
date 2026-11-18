import Foundation
import Testing
@testable import NastaTagCore

/// En tid i Stockholm: 16 november 2026 är en måndag.
private func at(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Rubrikerna under en timme, en per minut.
private func seen(_ label: String, day: Int, _ hour: Int, status: Status = .calm) -> Set<String> {
    Set((0..<60).map { departureMessage(status: status, minutes: 12, trainTime: at(day: day, hour, $0), label: label).headline })
}

@Test func wordsFollowTheTripAndTheDay() {
    #expect(seen("Jobbet", day: 16, 8).contains("Ny vecka, nya tåg."), "måndag mot jobbet")
    #expect(seen("Jobbet", day: 17, 8).contains("Morgonen är din."))
    #expect(seen("Jobbet", day: 20, 8).contains("Fredagsfeeling."))
    #expect(seen("Hem", day: 20, 16).contains("Helgen väntar.") || seen("Hem", day: 20, 16).contains("Snart helg."))
    #expect(seen("Hem", day: 17, 17).contains("Soffan väntar."))
    #expect(seen("Hem", day: 17, 23).contains("Sängen kallar."))
    #expect(seen("Hem", day: 21, 12).contains("Helg, ingen stress."), "lördag")
    // Fel stund, fel håll: inget soffprat på morgonen, ingen helg mitt i veckan.
    #expect(!seen("Jobbet", day: 17, 17).contains("Soffan väntar."))
    #expect(!seen("Hem", day: 18, 16).contains("Helgen väntar."))
    #expect(!seen("Hem", day: 17, 8).contains("Morgonen är din."))
    // Bara när det är lugnt. Bråttom är bråttom, vilken dag det än är.
    #expect(seen("Hem", day: 20, 16, status: .hurry).isSubset(of: Set(Voice.headlines[.hurry]!)))
}

@Test func theMomentShowsOftenButNotAlways() {
    let words = seen("Hem", day: 17, 17)
    let moment = Set(Voice.momentHeadlines(label: "Hem", trainTime: at(day: 17, 17)))
    let headlines = (0..<60).map { departureMessage(status: .calm, minutes: 12, trainTime: at(day: 17, 17, $0), label: "Hem").headline }
    let hits = headlines.filter { moment.contains($0) }.count
    #expect(hits > 15 && hits < 45, "ungefär hälften: \(hits) av 60")
    #expect(words.count > moment.count, "de vanliga orden finns kvar")
}

@Test func doneAndBoardedFollowTheDay() {
    let friday = (0..<60).map { at(day: 20, 17, $0) }
    let fridayBoarded = Set(friday.map { boardedHeadline(trainTime: $0, label: "Hem") })
    let wednesdayBoarded = Set((0..<60).map { boardedHeadline(trainTime: at(day: 18, 17, $0), label: "Hem") })
    let fridaySkips = Set(friday.map { skipWords(label: "Jobbet", trainTime: $0, mode: 2).done })
    #expect(fridayBoarded.contains("Trevlig helg."))
    #expect(!wednesdayBoarded.contains("Trevlig helg."))
    #expect(wednesdayBoarded.contains("Trevlig kväll."))
    #expect(fridaySkips.contains("Långhelg. Snyggt."))
}

@Test func momentWordsFitAndRead() {
    let times = (16...22).flatMap { day in [0, 8, 12, 15, 17, 22].map { at(day: day, $0) } }
    for time in times {
        for label in ["Hem", "Jobbet", "Gymmet"] {
            for line in Voice.momentHeadlines(label: label, trainTime: time) {
                #expect(line.count <= 20 && line.hasSuffix("."), "ryms på låsskärmen: \(line)")
                let hasNumber = line.contains { $0.isNumber }
                #expect(!hasNumber, "säger inget om tid: \(line)")
            }
            for line in Voice.momentBoarded(label: label, trainTime: time) + Voice.momentSkipDones(label: label, trainTime: time) {
                #expect(line.count <= 29 && line.hasSuffix("."), "\(line)")
                #expect(!line.contains("i dag") && !line.contains("i morgon"), "\(line)")
            }
        }
    }
}

/// Samma facit finns i webbens test, så att webben och telefonen väljer samma ord.
@Test func sameMomentWordsAsTheWeb() {
    let at = { (seconds: Double, label: String) in
        departureMessage(status: .calm, minutes: 9, trainTime: Date(timeIntervalSince1970: seconds), label: label).headline
    }
    #expect(at(1_794_931_200, "Hem") == "Middagen hägrar.")
    #expect(at(1_794_931_440, "Hem") == "Soffan väntar.")
    #expect(at(1_794_812_400, "Jobbet") == "Ny vecka, nya tåg.")
    let sunday = departureMessage(status: .calm, minutes: 3, trainTime: Date(timeIntervalSince1970: 1_794_721_920))
    #expect(sunday.headline == "Helg, ingen stress." && sunday.caption == "innan du behöver dra mot")
}
