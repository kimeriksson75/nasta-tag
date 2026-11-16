import Foundation
import NastaTagCore
import Testing

/// Rösten: alla kombinationer som kan visas ska vara hel svenska och säga en sak.
private let statuses: [Status] = [.calm, .hurry, .rush, .missed]
private let connectors = ["mot", "för", "med", "efter"]
/// Avgångar var tredje minut under ett helt dygn, så att alla varianter och morgonen kommer med.
private let times = (0..<480).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 180) }

@Test func everyHeadlineIsItsOwnSentence() {
    for status in statuses {
        for headline in Voice.headlines[status]! + Voice.morningHeadlines {
            #expect(headline.first?.isUppercase == true, "\(headline)")
            #expect(headline.hasSuffix(".") || headline.hasSuffix("!"), "\(headline)")
            #expect(!headline.contains("min"), "rubriken säger inget om tid: \(headline)")
        }
    }
}

@Test func everyCaptionLeadsIntoTheName() {
    for status in statuses {
        for caption in Voice.captions[status]! {
            #expect(caption.first?.isLowercase == true, "\(caption)")
            #expect(connectors.contains(String(caption.split(separator: " ").last!)), "\(caption)")
            // Annars ryms den inte på en rad i ringen.
            #expect(caption.count <= 24, "\(caption)")
        }
    }
}

@Test func everyScreenSaysOneThing() {
    for time in times {
        for status in statuses {
            let m = departureMessage(status: status, minutes: 3, trainTime: time)
            #expect(Voice.headlines(status, trainTime: time).contains(m.headline))
            #expect(!Voice.sharesWord(m.headline, m.caption), "\(m.headline) / \(m.caption)")
            #expect(!Voice.sharesWord(m.headline, m.wait), "\(m.headline) / \(m.wait)")
            let all = "\(m.headline) \(m.wait) \(m.caption)".lowercased()
            if status == .rush {
                #expect(!Voice.words(all).contains("gå"), "rött säger aldrig gå: \(all)")
            }
            if status == .calm || status == .hurry {
                for word in ["spring", "skynda", "fort", "fart"] { #expect(!all.contains(word), "\(all)") }
            }
            // Samma avgång ger alltid samma ord, så de inte byts medan du tittar.
            #expect(departureMessage(status: status, minutes: 2, trainTime: time).headline == m.headline)
        }
    }
}

@Test func theVoiceVaries() {
    for status in statuses {
        let seen = Set(times.map { departureMessage(status: status, minutes: 3, trainTime: $0).headline })
        #expect(Set(Voice.headlines[status]!).isSubset(of: seen), "\(status) visar inte alla rubriker")
    }
    let captions = Set(times.map { departureMessage(status: .hurry, minutes: 3, trainTime: $0).caption })
    #expect(captions.count == Voice.captions[.hurry]!.count)
}

@Test func coffeeOnlyInTheMorning() {
    for time in times {
        let headline = departureMessage(status: .calm, minutes: 8, trainTime: time).headline
        if headline == "Kaffet hinner du." {
            let hour = Calendar.current.dateComponents(in: TimeZone(identifier: "Europe/Stockholm")!, from: time).hour!
            #expect(hour < 10)
        }
    }
}

@Test func alertsAreWholeSentences() {
    for time in times {
        for status in [Status.hurry, .rush] {
            let message = departureMessage(status: status, minutes: 3, trainTime: time)
            let body = alertBody(status: status, minutes: 3, trainTime: time, mode: 2, label: "Hem")
            let name = tripName(time, mode: 2, "Hem")
            #expect(body.contains(name) && body.hasSuffix("."), "\(body)")
            #expect(!body.contains("{"), "\(body)")
            #expect(!Voice.sharesWord(message.headline, body.replacingOccurrences(of: name, with: "")),
                    "notisen upprepar rubriken: \(message.headline) / \(body)")
            if status == .rush { #expect(!Voice.words(body).contains("gå"), "\(body)") }
        }
    }
}
