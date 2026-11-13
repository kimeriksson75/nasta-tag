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

/// Rubriken säger bara hur läget är, aldrig något om tid, så den kan inte säga emot siffran under.
/// Tonen Lugn: samma korta ord varje gång, så att man känner igen läget utan att läsa.
private let headlines: [Status: [String]] = [
    .calm: ["Gott om tid."],
    .hurry: ["Skorna på."],
    .rush: ["Spring!"],
    .missed: ["Den har gått."],
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

/// Notisen när läget skärps: en hel mening av samma delar.
public func alertBody(status: Status, minutes: Int, trainTime: Date, mode: Int, label: String) -> String {
    let name = tripName(trainTime, mode: mode, label)
    return status == .rush ? "Gå nu så hinner du med \(name)." : "Gå om \(minutes) min för att hinna med \(name)."
}

public func tripPhrase(_ label: String) -> String {
    ["Hem": "hem", "Jobbet": "till jobbet"][label] ?? "till \(label)"
}
