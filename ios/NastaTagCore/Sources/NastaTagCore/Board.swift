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

private let leads: [Status: [String]] = [
    .calm: ["Ingen stress.\nDu behöver gå om", "Lugnt läge.\nDet räcker att gå om", "Gott om tid.\nDu kan gå om", "Ta en kaffe till.\nGå om"],
    .hurry: ["Raska på.\nDu behöver gå om", "Snart dags.\nDu behöver gå om", "Börja packa ihop.\nGå om", "Skorna på.\nDu behöver gå om"],
    .rush: ["Spring.\nDu behöver gå", "Nu gäller det.\nDu måste gå", "Full fart.\nGå", "Ut genom dörren.\nGå"],
]
private let bridges = ["för att hinna med", "så hinner du med", "så når du"]

public struct DepartureMessage: Equatable, Sendable {
    public var lead: String
    public var wait: String
    public var bridge: String
}

/// Orden följer avgången, så att de inte byts varje gång skärmen ritas om.
/// Minuterna rundas nedåt: hellre en minut för tidigt än ett missat tåg.
public func departureMessage(_ train: Train) -> DepartureMessage {
    let seed = Int(train.time.timeIntervalSince1970 / 60)
    func pick(_ list: [String]) -> String { list[seed % list.count] }
    return DepartureMessage(
        lead: pick(leads[train.status] ?? leads[.calm]!),
        wait: train.status == .rush ? "nu" : "\(Int(train.slackMinutes.rounded(.down))) min",
        bridge: pick(bridges)
    )
}

public func tripPhrase(_ label: String) -> String {
    ["Hem": "hem", "Jobbet": "till jobbet"][label] ?? "till \(label)"
}
