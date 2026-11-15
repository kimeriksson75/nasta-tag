import Foundation
import Testing
@testable import NastaTagCore

// Grönt, gult och rött: allt som bär lägets färg ska byta samtidigt och aldrig hamna i ett mellanläge.

private let leaveAt = Date(timeIntervalSince1970: 1_800_000_000)

/// Det skärmen visar när läget räknas ut: rubriken, rubrikens och knappens färg, och ringen.
private struct Screen {
    var headline: String
    var headlineHex: String
    var buttonHex: String
    var ringHex: String
}

private func screen(stateAt now: Date, ringAt frame: Date) -> Screen {
    let status = classify(leaveAt.timeIntervalSince(now) / 60)
    let mood = Mood(status)
    let ring = ringTarget(leaveAt: leaveAt, mood: mood, now: frame)
    return Screen(headline: departureMessage(status: status, minutes: 3, trainTime: leaveAt).headline,
                  headlineHex: mood.accentHex, buttonHex: mood.accentHex, ringHex: ring.mood.accentHex)
}

/// Varje läge har en egen färg och en egen rubrik, och de hör alltid ihop.
private let pairs: [String: String] = [
    Mood.calm.accentHex: "Gott om tid.",
    Mood.hurry.accentHex: "Skorna på.",
    Mood.rush.accentHex: "Spring!",
    Mood.idle.accentHex: "Den har gått.",
]

@Test func fourStatesFourColours() {
    #expect(Set([Mood.idle, .calm, .hurry, .rush].map(\.accentHex)).count == 4)
    #expect(Mood(.missed) == .idle && Mood(nil) == .idle)
}

@Test func everythingSharesOneState() {
    // Varje sekund från 20 minuter före till en minut efter att du skulle gått.
    for second in stride(from: -20 * 60, through: 60, by: 1) {
        let now = leaveAt.addingTimeInterval(TimeInterval(second))
        let shown = screen(stateAt: now, ringAt: now)
        #expect(shown.ringHex == shown.headlineHex, "ringen och rubriken skiljer sig \(second) s från att gå")
        #expect(shown.buttonHex == shown.headlineHex)
        #expect(pairs[shown.headlineHex] == shown.headline, "rubriken passar inte färgen \(second) s från att gå")
    }
}

@Test func ringNeverRunsAheadOfTheHeadline() {
    // Ringen ritas varje bildruta, läget räknas om var femte sekund. Även när ringens bildruta
    // ligger fem sekunder före läget, alldeles vid ett byte, har den samma färg som rubriken.
    for limit in [hurryLimitMinutes, rushLimitMinutes, 0] {
        let stateAt = leaveAt.addingTimeInterval(-limit * 60 - 1)
        for lag in 0...5 {
            let shown = screen(stateAt: stateAt, ringAt: stateAt.addingTimeInterval(TimeInterval(lag)))
            #expect(shown.ringHex == shown.headlineHex, "ringen bytte före rubriken vid \(limit) min")
        }
    }
}

@Test func noColourBetweenStates() {
    // Ringen tonar inte mot nästa läge: 2,5 minuter kvar är gult rakt igenom, inte orange.
    let ring = ringTarget(leaveAt: leaveAt, mood: Mood(classify(2.5)), now: leaveAt.addingTimeInterval(-150))
    #expect(ring.mood == .hurry)
    let seen = Set(stride(from: -60, through: 20 * 60, by: 1).map { second -> String in
        let now = leaveAt.addingTimeInterval(TimeInterval(-second))
        return ringTarget(leaveAt: leaveAt, mood: Mood(classify(Double(second) / 60)), now: now).mood.accentHex
    })
    #expect(seen == Set(pairs.keys))
}

@Test func statesChangeExactlyAtTheLimits() {
    #expect(classify(hurryLimitMinutes) == .calm)
    #expect(classify(hurryLimitMinutes - 0.001) == .hurry)
    #expect(classify(rushLimitMinutes) == .hurry)
    #expect(classify(rushLimitMinutes - 0.001) == .rush)
    #expect(classify(0) == .rush)
    #expect(classify(-0.001) == .missed)
}

@Test func ringEmptiesAsTimeRunsOut() {
    let full = ringTarget(leaveAt: leaveAt, mood: .calm, now: leaveAt.addingTimeInterval(-20 * 60))
    let half = ringTarget(leaveAt: leaveAt, mood: .calm, now: leaveAt.addingTimeInterval(-7.5 * 60))
    let late = ringTarget(leaveAt: leaveAt, mood: .rush, now: leaveAt.addingTimeInterval(3))
    #expect(full.fraction == 1)
    #expect(abs(half.fraction - 0.5) < 0.0001)
    #expect(late.fraction == 0.04 && late.mood == .rush) // en sliver kvar tills läget hinner bli Missad
    #expect(ringTarget(leaveAt: nil, mood: .calm, now: leaveAt) == RingTarget(fraction: 0, mood: .idle))
    #expect(ringTarget(leaveAt: leaveAt, mood: .idle, now: leaveAt).fraction == 0)
}
