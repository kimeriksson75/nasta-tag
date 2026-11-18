import Foundation

// Orden efter resa och tid på dygnet: vart du ska och när avgången går, i Stockholmstid.
// De blandas med de vanliga orden, så att samma rad inte kommer varje dag.

/// Veckodag i Stockholm, 1 är söndag och 7 lördag.
func stockholmWeekday(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar.component(.weekday, from: date)
}

private let monday = 2, friday = 6, saturday = 7, sunday = 1

extension Voice {
    /// Lugna rubriker för stunden. Säger aldrig något om tid, som de vanliga.
    public static func momentHeadlines(label: String?, trainTime: Date) -> [String] {
        let hour = stockholmHour(trainTime), day = stockholmWeekday(trainTime)
        if day == saturday || day == sunday { return ["Helg, ingen stress."] }
        switch label {
        case "Jobbet":
            if day == monday { return ["Ny vecka, nya tåg."] }
            if day == friday { return ["Fredagsfeeling."] }
            return hour < 10 ? ["Morgonen är din."] : []
        case "Hem":
            if hour >= 21 || hour < 4 { return ["Sängen kallar.", "Kvällen är ung."] }
            if day == friday && hour >= 14 { return ["Helgen väntar.", "Snart helg."] }
            if hour >= 16 { return ["Soffan väntar.", "Middagen hägrar."] }
            return []
        default:
            return []
        }
    }

    /// När tåget har gått med dig.
    public static func momentBoarded(label: String?, trainTime: Date) -> [String] {
        let hour = stockholmHour(trainTime), day = stockholmWeekday(trainTime)
        switch label {
        case "Jobbet":
            return day == friday ? ["Sista dagen. Kör hårt."] : hour < 11 ? ["Ha en bra dag."] : []
        case "Hem":
            if day == friday && hour >= 14 { return ["Trevlig helg."] }
            return hour >= 16 || hour < 4 ? ["Trevlig kväll."] : []
        default:
            return []
        }
    }

    /// Efter att du struntat i resan.
    public static func momentSkipDones(label: String?, trainTime: Date) -> [String] {
        let day = stockholmWeekday(trainTime)
        switch label {
        case "Jobbet": return day == friday ? ["Långhelg. Snyggt."] : day == monday ? ["Måndagen kan vänta."] : []
        case "Hem": return day == friday ? ["Fredag. Du förtjänar det."] : []
        default: return []
        }
    }
}

/// Ord för stunden får två platser i listan, så att de syns ungefär hälften av gångerna
/// i stället för en gång av sex.
func withMoment(_ list: [String], _ moment: [String]) -> [String] { list + moment + moment }
