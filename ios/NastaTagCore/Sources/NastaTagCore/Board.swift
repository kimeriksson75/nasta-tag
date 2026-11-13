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

/// En avgång som SL:s öppna API skickar den.
public struct Departure: Decodable, Sendable {
    public struct Line: Decodable, Sendable { public var designation: String }
    public struct Journey: Decodable, Sendable { public var id: Int }
    public struct Deviation: Decodable, Sendable { public var consequence: String? }

    public var destination: String
    public var state: String?
    public var scheduled: String
    public var expected: String?
    public var line: Line
    public var journey: Journey?
    public var deviations: [Deviation]?

    var isRunning: Bool {
        if let state, ["CANCELLED", "PASSED", "NOTCALLED", "REPLACED"].contains(state) { return false }
        return !(deviations ?? []).contains { $0.consequence == "CANCELLED" }
    }
}

/// SL skickar tider utan tidszon, i Stockholmstid.
public func stockholmDate(_ text: String) -> Date? {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(identifier: "Europe/Stockholm")
    parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return parser.date(from: text)
}

public struct Train: Hashable, Sendable, Identifiable {
    public var time: Date
    public var minutesLeft: Double
    public var slackMinutes: Double
    public var leaveBy: Date
    public var status: Status
    public var journey: Int?
    public var line: String
    public var destination: String
    public var id: String { "\(journey ?? 0)-\(time.timeIntervalSince1970)" }
}

/// Tåg mot målet, sorterade på tid, med marginal efter gångtiden.
public func buildBoard(departures: [Departure], metro: Metro, from: String, target: String, now: Date, walkMinutes: Double) -> [Train] {
    departures
        .filter { $0.isRunning && metro.trainReaches(from: from, destination: $0.destination, target: target) }
        .compactMap { departure -> Train? in
            guard let time = stockholmDate(departure.expected ?? departure.scheduled) else { return nil }
            let minutesLeft = time.timeIntervalSince(now) / 60
            let slack = minutesLeft - walkMinutes
            return Train(time: time, minutesLeft: minutesLeft, slackMinutes: slack,
                         leaveBy: time.addingTimeInterval(-walkMinutes * 60), status: classify(slack),
                         journey: departure.journey?.id, line: departure.line.designation, destination: departure.destination)
        }
        .filter { $0.minutesLeft > -0.5 }
        .sorted { $0.time < $1.time }
}

/// Rubriken säger bara hur läget är, aldrig något om tid, så den kan inte säga emot siffran under.
private let headlines: [Status: [String]] = [
    .calm: ["Gott om tid.", "Ingen stress.", "Lugnt läge.", "Hinner en kaffe till."],
    .hurry: ["Snart dags.", "Skorna på.", "Börja runda av.", "Dags att röra på sig."],
    .rush: ["Spring!", "Ut genom dörren!", "Nu gäller det!", "Full fart!"],
    .missed: ["Tåget har gått."],
]

/// Samma meddelande överallt, i appen, på låsskärmen och i notisen:
/// rubrik, när du ska gå och vad det leder till.
///
///     Gott om tid.     Spring!
///     8 min            Gå nu
///     tills du går     så hinner du med
public struct DepartureMessage: Equatable, Sendable {
    public var headline: String
    public var wait: String
    public var caption: String
}

/// Hela minuter tills du behöver gå, rundat nedåt: hellre en minut för tidigt än ett missat tåg.
public func minutesToLeave(_ slackMinutes: Double) -> Int { max(0, Int(slackMinutes.rounded(.down))) }

/// Orden följer avgången, så att de inte byts varje gång skärmen ritas om.
public func departureMessage(status: Status, minutes: Int, trainTime: Date) -> DepartureMessage {
    let list = headlines[status] ?? headlines[.calm]!
    let headline = list[Int(trainTime.timeIntervalSince1970 / 60) % list.count]
    switch status {
    case .calm, .hurry: return DepartureMessage(headline: headline, wait: "\(minutes) min", caption: "tills du ska gå")
    case .rush: return DepartureMessage(headline: headline, wait: "Gå nu", caption: "så hinner du med")
    case .missed: return DepartureMessage(headline: headline, wait: "–", caption: "Ta nästa")
    }
}

public func departureMessage(_ train: Train) -> DepartureMessage {
    departureMessage(status: train.status, minutes: minutesToLeave(train.slackMinutes), trainTime: train.time)
}

/// "16:40-tåget hem"
public func trainName(_ time: Date, _ label: String) -> String {
    "\(time.formatted(date: .omitted, time: .shortened))-tåget \(tripPhrase(label))"
}

/// Notisen när läget skärps: en hel mening av samma delar.
public func alertBody(status: Status, minutes: Int, trainTime: Date, label: String) -> String {
    let name = trainName(trainTime, label)
    return status == .rush ? "Gå nu så hinner du med \(name)." : "Gå om \(minutes) min för att hinna med \(name)."
}

public func tripPhrase(_ label: String) -> String {
    ["Hem": "hem", "Jobbet": "till jobbet"][label] ?? "till \(label)"
}
