import Foundation

// Meddelandet till den som väntar, när tåget har gått med dig. Det ska låta som du, inte som en app:
// ingen länk, ingen adress, ingen hållplats. Tiden är ett löfte, så med ett byte kvar står det "runt".

/// Knappen på Trevlig kväll-skärmen och texten den delar.
public struct TellWords: Equatable, Sendable {
    public var button: String
    public var message: String
}

extension Voice {
    // {n} är fordonet, {t} när du är framme, {p} "till Gymmet".
    public static let tellHome = ["Sitter på {n}. Hemma {t}, sätt på något gott.", "På {n} nu. Hemma {t}, gör plats i soffan.",
                                  "Hann med {n}. Hemma {t}, applåder mottages.", "På {n}. Hemma {t}. Längtar redan."]
    public static let tellHomeLate = ["På {n}. Hemma {t}. Väck mig inte om jag somnar på soffan.", "Sitter på {n}. Hemma {t}, jag tassar in.",
                                      "På {n} nu. Hemma {t}. Lämna en lampa tänd."]
    public static let tellHomeDay = ["Sitter på {n}. Hemma {t}.", "På {n} nu. Hemma {t}, sätt på kaffet.", "Hann med {n}. Hemma {t}, applåder mottages."]
    public static let tellWork = ["På {n}. Inne {t}. Börja utan mig, men inte kaffet.", "Sitter på {n}. Inne {t}, håll en stol varm.",
                                  "Hann med {n}. Inne {t}. Se upptagna ut."]
    public static let tellOther = ["På väg {p}. Framme {t}. Ingen återvändo nu.", "Sitter på {n} {p}. Framme {t}.", "Hann med {n}. Framme {t}, applåder mottages."]
}

/// Samma resa ger alltid samma ord, olika resor blandar.
public func tellWords(_ trip: Trip, label: String) -> TellWords {
    let hour = stockholmHour(trip.arrival)
    let list: [String], button: String
    switch label {
    case "Hem":
        button = "Säg till hemma"
        list = hour >= 22 || hour < 5 ? Voice.tellHomeLate : hour >= 16 ? Voice.tellHome : Voice.tellHomeDay
    case "Jobbet":
        button = "Säg till jobbet"
        list = Voice.tellWork
    default:
        button = "Säg till"
        list = Voice.tellOther
    }
    let clock = stockholmClock(trip.arrival)
    let message = Voice.pick(list, seed: trip.time, salt: 30)
        .replacingOccurrences(of: "{n}", with: Mode(trip.mode).noun)
        .replacingOccurrences(of: "{t}", with: trip.transfers.isEmpty ? clock : "runt \(clock)")
        .replacingOccurrences(of: "{p}", with: tripPhrase(label))
    return TellWords(button: button, message: message)
}
