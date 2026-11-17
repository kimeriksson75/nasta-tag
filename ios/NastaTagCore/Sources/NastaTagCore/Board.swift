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
        .calm: ["Gott om tid.", "Ingen brådska.", "Du hinner.", "Luta dig tillbaka.", "Häng kvar en stund."],
        .hurry: ["På med skorna.", "Börja avrunda.", "Samla ihop grejerna.", "Dags att röra på sig.", "Snart dags."],
        // Kort, för att det är bråttom. Du hinner fortfarande om du går raskt, så "Spring!" är en glimt i ögat.
        .rush: ["Spring!", "Nu gäller det!", "Raska steg!", "Full fart!", "Iväg med dig!"],
        // Tåget har oftast inte gått än, det är du som inte hinner. Orden säger det.
        .missed: ["Den hinner du inte.", "Släpp den.", "Den får gå utan dig.", "Det kommer fler.", "Missad. Ingen fara."],
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

    /// Rubrikerna som kan visas för en avgång vid den tiden, och vart du ska.
    public static func headlines(_ status: Status, trainTime: Date, label: String? = nil) -> [String] {
        let list = headlines[status] ?? []
        guard status == .calm else { return list }
        let morning = stockholmHour(trainTime) < 10 ? morningHeadlines : []
        return withMoment(list + morning, momentHeadlines(label: label, trainTime: trainTime))
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
    /// Vädret, när det är värt att nämna.
    public var weather: Weather? = nil

    /// Rubriken med vädrets emoji framför, som den visas.
    public var title: String { weather.map { "\($0.emoji) \(headline)" } ?? headline }
}

/// Hela minuter tills du behöver gå, rundat nedåt: hellre en minut för tidigt än ett missat tåg.
public func minutesToLeave(_ slackMinutes: Double) -> Int { max(0, Int(slackMinutes.rounded(.down))) }

/// Orden följer avgången, så att de inte byts varje gång skärmen ritas om.
/// Vädret ersätter rubriken när det är Snart, för då klär du på dig. Lugnt får bara emojin,
/// och när det är bråttom byts orden bara vid halka. En missad avgång bryr sig inte om vädret.
public func departureMessage(status: Status, minutes: Int, trainTime: Date, weather: Weather? = nil, label: String? = nil) -> DepartureMessage {
    let weather = status == .missed ? nil : weather
    let weatherWords = weather.flatMap { (status == .rush ? Voice.weatherRushHeadlines : status == .hurry ? Voice.weatherHeadlines : [:])[$0] }
    let headline = Voice.pick(weatherWords ?? Voice.headlines(status, trainTime: trainTime, label: label), seed: trainTime, salt: 1)
    let wait: String
    switch status {
    case .calm, .hurry: wait = "\(minutes) min"
    case .rush: wait = Voice.pick(Voice.rushWords, seed: trainTime, salt: 2, avoiding: headline)
    case .missed: wait = "–"
    }
    let caption = Voice.pick(Voice.captions[status] ?? [], seed: trainTime, salt: 3, avoiding: headline)
    return DepartureMessage(headline: headline, wait: wait, caption: caption, weather: weather)
}

public func departureMessage(_ trip: Trip, weather: Weather? = nil, label: String? = nil) -> DepartureMessage {
    departureMessage(status: trip.status, minutes: minutesToLeave(trip.slackMinutes), trainTime: trip.time, weather: weather, label: label)
}

/// "16:40-bussen hem"
public func tripName(_ time: Date, mode: Int, _ label: String) -> String {
    "\(stockholmClock(time))-\(Mode(mode).noun) \(tripPhrase(label))"
}

public func tripName(_ trip: Trip, _ label: String) -> String { tripName(trip.time, mode: trip.mode, label) }

/// Klockslag i Stockholmstid, oavsett vilken tidszon telefonen står i.
public func stockholmClock(_ date: Date) -> String {
    clockFormatter.string(from: date)
}

/// Notisen när läget skärps: en hel mening, som inte upprepar rubriken den står under.
public func alertBody(status: Status, minutes: Int, trainTime: Date, mode: Int, label: String, weather: Weather? = nil) -> String {
    let name = tripName(trainTime, mode: mode, label)
    let headline = departureMessage(status: status, minutes: minutes, trainTime: trainTime, weather: weather, label: label).headline
    let list = status == .rush ? Voice.rushAlerts : Voice.hurryAlerts
    return Voice.pick(list, seed: trainTime, salt: 4, avoiding: headline)
        .replacingOccurrences(of: "{m}", with: "\(minutes)")
        .replacingOccurrences(of: "{n}", with: name)
}

public func tripPhrase(_ label: String) -> String {
    ["Hem": "hem", "Jobbet": "till jobbet"][label] ?? "till \(label)"
}

/// Raden under resan: linjen, hållplatsen, bytena och när du är framme. Riktningen behövs först
/// vid perrongen, så hemma och på väg får ankomsten dess plats och raden blir inte längre.
public func tripLine(_ trip: Trip, label: String?, atStop: Bool) -> String {
    let line = atStop ? trip.lineText : "\(Mode(trip.mode).line) \(trip.line)"
    return (["\(line) från \(trip.stop.name)"] + trip.transfers.map { "byte \($0)" }
        + [arrivalPhrase(label, arrival: trip.arrival)]).joined(separator: " · ")
}

/// När du är framme, med platsens ord: "hemma 08:02", "på jobbet 08:02", annars "framme 08:02".
public func arrivalPhrase(_ label: String?, arrival: Date) -> String {
    let words = label.flatMap { ["Hem": "hemma", "Jobbet": "på jobbet"][$0] } ?? "framme"
    return "\(words) \(stockholmClock(arrival))"
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
    public static let skipButtonsWork = ["Sängen vinner.", "Jobbet klarar sig."]
    public static let skipButtonsHome = ["En öl till.", "Vi tar en till."]
    public static let skipButtonsOther = ["Inte idag."]
    public static let skipAsks = ["Dra en rövare?", "Strunta i det idag?", "Ska vi skippa idag?"]
    public static let skipAsksWork = ["Ledig idag?", "Ta en spontan ledig dag?"]
    public static let skipConfirm = "Ja!"
    public static let skipCancel = "Nej 🙁"
    public static let skipDones = ["Snyggt. Vi hörs imorgon.", "Livet är mer än tidtabeller.",
                                   "Klokt? Oklart. Skönt? Absolut.", "Bra val. {N} klarar sig."]
    public static let skipDonesWork = ["Ibland vinner soffan."]
}

/// Orden följer avgången och vart du ska: "Sängen vinner." bara mot jobbet, "En öl till." bara hem.
public func skipWords(label: String, trainTime: Date, mode: Int) -> SkipWords {
    let extra = label == "Jobbet" ? Voice.skipButtonsWork : label == "Hem" ? Voice.skipButtonsHome : Voice.skipButtonsOther
    let button = Voice.pick(Voice.skipButtons + extra, seed: trainTime, salt: 5)
    let asks = Voice.skipAsks + (label == "Jobbet" ? Voice.skipAsksWork : [])
    let ask = Voice.pick(asks, seed: trainTime, salt: 6, avoiding: button)
    let noun = Mode(mode).noun
    let dones = withMoment(Voice.skipDones + (label == "Jobbet" ? Voice.skipDonesWork : []),
                           Voice.momentSkipDones(label: label, trainTime: trainTime))
    let done = Voice.pick(dones, seed: trainTime, salt: 7, avoiding: button)
        .replacingOccurrences(of: "{N}", with: noun.prefix(1).uppercased() + noun.dropFirst())
    return SkipWords(button: button, ask: ask, detail: "Vi slutar påminna dig om \(noun) idag.", done: done)
}

/// Dagen i Stockholm, "2026-11-15", så att ett "strunta i det" gäller till midnatt.
public func stockholmDay(_ date: Date) -> String {
    dayFormatter.string(from: date)
}

private func stockholmFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "sv_SE")
    formatter.timeZone = TimeZone(identifier: "Europe/Stockholm")
    formatter.dateFormat = format
    return formatter
}
nonisolated(unsafe) private let clockFormatter = stockholmFormatter("HH:mm")
nonisolated(unsafe) private let dayFormatter = stockholmFormatter("yyyy-MM-dd")
