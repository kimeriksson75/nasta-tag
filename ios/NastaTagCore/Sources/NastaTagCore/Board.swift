import Foundation

public enum Status: String, Codable, Hashable, Sendable {
    case calm, hurry, rush, missed
}

public let rushLimitMinutes = 2.0 // under så här mycket marginal: spring
public let hurryLimitMinutes = 5.0 // under så här mycket marginal: raska på

public func classify(_ slackMinutes: Double) -> Status {
    if slackMinutes < 0 { return .missed }
    if slackMinutes < rushLimitMinutes { return .rush }
    if slackMinutes < hurryLimitMinutes { return .hurry }
    return .calm
}

/// Rösten: som en kompis som kan tidtabellen. Kort, varm, lite kaxig, aldrig tjatig.
/// Ju mer bråttom, desto kortare. Samma sak sägs på flera sätt, och orden byts när avgången byts,
/// aldrig medan du tittar.
///
/// Rubriken är en egen mening. Siffran, raden under och avgångens namn läses ihop till en mening:
///
///     Häng kvar en stund.        Jackan på.                Spring!
///     11 min                     3 min                     Nu
///     tills du ska gå mot        sen drar du mot           så hinner du med
///     16:30-tåget hem            16:30-tåget hem           16:34-tåget hem
public enum Voice {
    /// Rubriken säger bara hur läget är, aldrig något om tid, så den kan inte säga emot siffran.
    public static let headlines: [Status: [String]] = [
        .calm: ["Gott om tid.", "Ingen stress.", "Lugnt läge.", "Du ligger bra till.",
                "Häng kvar en stund.", "Allt under kontroll.", "Luta dig tillbaka."],
        .hurry: ["Skorna på.", "Jackan på.", "Gör dig redo.", "Plocka ihop grejerna.",
                 "Dags att röra på sig.", "Snart dags.", "Nu närmar det sig."],
        .rush: ["Spring!", "Full fart!", "Iväg med dig!", "Benen på ryggen!", "Nu kör vi!", "Dags att sticka!"],
        // Tåget har oftast inte gått än, det är du som inte hinner. Orden säger det.
        .missed: ["Den hinner du inte.", "Släpp den.", "Den får gå utan dig.", "Missad. Ingen fara."],
    ]
    /// Bara på morgonen, när avgången går före tio.
    public static let morningHeadlines = ["Kaffet hinner du."]

    /// Raden under siffran: liten bokstav, ingen punkt, och den slutar där avgångens namn tar vid.
    public static let captions: [Status: [String]] = [
        .calm: ["tills du behöver gå mot", "tills du ska gå mot", "innan du behöver dra mot", "kvar innan du ska gå mot"],
        .hurry: ["tills du behöver gå mot", "sen drar du mot", "sen är det dags för", "kvar innan du ska gå mot"],
        .rush: ["så hinner du med", "om du ska hinna med", "för att hinna med"],
        .missed: ["ta nästa efter"],
    ]
    /// Det stora ordet i ringen när det är bråttom. Aldrig "gå".
    public static let rushWords = ["Nu", "Iväg", "Kör"]

    /// Notisen när det blir gult eller rött. {m} är minuter, {n} avgångens namn.
    public static let hurryAlerts = ["Gå om {m} min, så hinner du med {n}.", "Om {m} min behöver du gå mot {n}.",
                                     "Skorna på. Om {m} min går du mot {n}.", "Snart dags: {n} vill ha dig om {m} min."]
    public static let rushAlerts = ["Spring nu, så hinner du med {n}.", "Iväg nu om du ska hinna med {n}.",
                                    "Nu kör vi. {n} väntar inte.", "Full fart, så hinner du med {n}."]

    /// Småord som får finnas i både rubriken och raden under.
    static let smallWords: Set<String> = ["du", "att", "så", "med", "om", "på", "i", "en", "det", "är",
                                          "för", "mot", "till", "efter", "sen", "vi", "dig"]

    /// Orden som bär betydelse, så att rubriken och raden under inte upprepar varandra.
    public static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { !smallWords.contains($0) })
    }

    public static func sharesWord(_ a: String, _ b: String) -> Bool { !words(a).isDisjoint(with: words(b)) }

    /// Rubrikerna som kan visas för en avgång vid den tiden.
    public static func headlines(_ status: Status, trainTime: Date) -> [String] {
        let list = headlines[status] ?? []
        return status == .calm && stockholmHour(trainTime) < 10 ? list + morningHeadlines : list
    }

    /// Samma avgång ger alltid samma ord, olika avgångar blandar. `salt` skiljer valen åt.
    static func pick(_ list: [String], seed: Date, salt: UInt64, avoiding other: String? = nil) -> String {
        let fitting = other.map { other in list.filter { !sharesWord($0, other) } } ?? list
        let options = fitting.isEmpty ? list : fitting
        var x = UInt64(bitPattern: Int64(seed.timeIntervalSince1970 / 60)) &+ salt &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return options[Int(x % UInt64(options.count))]
    }
}

func stockholmHour(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar.component(.hour, from: date)
}

public struct DepartureMessage: Equatable, Sendable {
    public var headline: String
    public var wait: String
    public var caption: String
}

/// Hela minuter tills du behöver gå, rundat nedåt: hellre en minut för tidigt än ett missat tåg.
public func minutesToLeave(_ slackMinutes: Double) -> Int { max(0, Int(slackMinutes.rounded(.down))) }

/// Orden följer avgången, så att de inte byts varje gång skärmen ritas om.
public func departureMessage(status: Status, minutes: Int, trainTime: Date) -> DepartureMessage {
    let headline = Voice.pick(Voice.headlines(status, trainTime: trainTime), seed: trainTime, salt: 1)
    let wait: String
    switch status {
    case .calm, .hurry: wait = "\(minutes) min"
    case .rush: wait = Voice.pick(Voice.rushWords, seed: trainTime, salt: 2, avoiding: headline)
    case .missed: wait = "–"
    }
    let caption = Voice.pick(Voice.captions[status] ?? [], seed: trainTime, salt: 3, avoiding: headline)
    return DepartureMessage(headline: headline, wait: wait, caption: caption)
}

public func departureMessage(_ trip: Trip) -> DepartureMessage {
    departureMessage(status: trip.status, minutes: minutesToLeave(trip.slackMinutes), trainTime: trip.time)
}

/// "16:40-bussen hem"
public func tripName(_ time: Date, mode: Int, _ label: String) -> String {
    "\(stockholmClock(time))-\(Mode(mode).noun) \(tripPhrase(label))"
}

public func tripName(_ trip: Trip, _ label: String) -> String { tripName(trip.time, mode: trip.mode, label) }

/// Klockslag i Stockholmstid, oavsett vilken tidszon telefonen står i.
public func stockholmClock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "sv_SE")
    formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

/// Notisen när läget skärps: en hel mening, som inte upprepar rubriken den står under.
public func alertBody(status: Status, minutes: Int, trainTime: Date, mode: Int, label: String) -> String {
    let name = tripName(trainTime, mode: mode, label)
    let headline = departureMessage(status: status, minutes: minutes, trainTime: trainTime).headline
    let list = status == .rush ? Voice.rushAlerts : Voice.hurryAlerts
    return Voice.pick(list, seed: trainTime, salt: 4, avoiding: headline)
        .replacingOccurrences(of: "{m}", with: "\(minutes)")
        .replacingOccurrences(of: "{n}", with: name)
}

public func tripPhrase(_ label: String) -> String {
    ["Hem": "hem", "Jobbet": "till jobbet"][label] ?? "till \(label)"
}

// MARK: Strunta i resan

/// Orden när du redan har snoozat och hellre struntar i resan idag. Appen håller med, den ifrågasätter inte.
public struct SkipWords: Equatable, Sendable {
    /// Knappen där Snooze satt. Kort, den ska rymmas på en rad.
    public var button: String
    /// Rutans fråga.
    public var ask: String
    /// Raden i rutan som säger rakt vad som händer.
    public var detail: String
    /// Det som står på skärmen efteråt.
    public var done: String
}

extension Voice {
    public static let skipButtons = ["Fuck it.", "Skit i det."]
    public static let skipButtonsWork = ["Sängen vinner.", "Ledig dag."]
    public static let skipButtonsHome = ["En öl till."]
    public static let skipButtonsOther = ["Skippa idag."]
    public static let skipAsks = ["Dra en rövare?", "Strunta i det idag?"]
    public static let skipAsksWork = ["Ledig dag?"]
    public static let skipConfirm = "Kör!"
    public static let skipCancel = "Nej, jag går"
    public static let skipDones = ["Snyggt. Vi hörs i morgon.", "Njut. Vi ses i morgon.", "Okej, ingen fara. Vi hörs.",
                                   "Bra val. {N} klarar sig."]
}

/// Orden följer avgången och vart du ska: "Sängen vinner." bara mot jobbet, "En öl till." bara hem.
public func skipWords(label: String, trainTime: Date, mode: Int) -> SkipWords {
    let extra = label == "Jobbet" ? Voice.skipButtonsWork : label == "Hem" ? Voice.skipButtonsHome : Voice.skipButtonsOther
    let button = Voice.pick(Voice.skipButtons + extra, seed: trainTime, salt: 5)
    let asks = Voice.skipAsks + (label == "Jobbet" ? Voice.skipAsksWork : [])
    let ask = Voice.pick(asks, seed: trainTime, salt: 6, avoiding: button)
    let noun = Mode(mode).noun
    let done = Voice.pick(Voice.skipDones, seed: trainTime, salt: 7)
        .replacingOccurrences(of: "{N}", with: noun.prefix(1).uppercased() + noun.dropFirst())
    return SkipWords(button: button, ask: ask, detail: "Vi slutar påminna dig om \(noun) idag.", done: done)
}

/// Dagen i Stockholm, "2026-11-15", så att ett "strunta i det" gäller till midnatt.
public func stockholmDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "sv_SE")
    formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
