import Foundation

// Notiserna när du följer en resa. "Följ på låsskärmen" är notisknappen: följer du ingen resa kommer
// inga. Är du kvar får du högst två, och har du börjat gå kommer inga alls, utom om avgången ställs in
// eller ändras så att du inte hinner. Reglerna bestäms här och appen schemalägger dem.

/// De två notiserna medan du är kvar. Samma gränser som gult och rött, så att notisen och kortet säger samma sak.
public enum FollowAlert: String, Codable, CaseIterable, Sendable {
    /// Dags att gå om fem minuter.
    case soon
    /// Gå nu. Kommer när kortet blir rött, medan du fortfarande hinner.
    case go

    public var minutesBefore: Double { self == .soon ? hurryLimitMinutes : rushLimitMinutes }
    public var status: Status { self == .soon ? .hurry : .rush }

    /// Notisens id. Ett per sort, så att en ny alltid ersätter den gamla.
    public var id: String { "follow.\(rawValue)" }
    public static let changeId = "follow.change"
    public static let allIds = allCases.map(\.id) + [changeId]
}

/// Var du är i resan, det som notiserna bryr sig om.
public enum FollowSpot: Equatable, Sendable {
    /// Vid en av dina platser, eller innan du har kommit i gång någon annanstans.
    case stillHere(atPlace: Bool)
    case walking
    case atStop
}

/// Varför den följda avgången inte längre går att ta.
public enum FollowChange: Equatable, Sendable {
    /// Avgången är inställd.
    case cancelled
    /// Ett byte senare på resan hinns inte längre eller är inställt.
    case connectionLost
    /// Avgången går tidigare än den gjorde, och du hinner inte.
    case earlier
}

/// Vad som har hänt med en följd avgång som inte längre går att ta, enligt SL:s svar.
/// Nil när den går som den ska, eller när svaren inte säger något om den.
public func followChange(_ journeys: [Journey], key: String) -> FollowChange? {
    let mine = journeys.filter { departureKey($0) == key }
    guard !mine.isEmpty, !mine.contains(where: { parseJourney($0) != nil }) else { return nil }
    let first = mine.compactMap { journey in journey.legs.first { !isWalk($0) } }
    if first.contains(where: isCancelled) { return .cancelled }
    if mine.allSatisfy({ $0.legs.contains(where: isCancelled) || !connectionsHold($0.legs) }) { return .connectionLost }
    return nil
}

/// Det appen minns om den följda resans notiser. Sparas, så att en omstart inte skickar dem igen.
public struct FollowAlerts: Codable, Equatable, Sendable {
    public private(set) var key: String?
    /// När avgången gick när du började följa den.
    private var firstTime: Date?
    /// Du har börjat gå. Står kvar även om appen byter avgång på vägen, tills du är tillbaka vid en plats.
    public private(set) var left = false
    private var planned: [FollowAlert: Date] = [:]
    private var sent: Set<FollowAlert> = []
    private var warned = false

    public init() {}

    /// Notiserna som ska ligga schemalagda nu. Ändras tiderna kommer nya tider för samma notiser,
    /// och en som redan har kommit för avgången kommer inte igen.
    public mutating func plan(_ trip: Trip, spot: FollowSpot, now: Date) -> [FollowAlert: Date] {
        noteSent(now: now)
        retarget(trip)
        switch spot {
        case .walking, .atStop: left = true
        case .stillHere(let atPlace): if atPlace { left = false }
        }
        planned = [:]
        guard !left, trip.status != .missed else { return [:] }
        for alert in FollowAlert.allCases where !sent.contains(alert) {
            let at = trip.leaveAt.addingTimeInterval(-alert.minutesBefore * 60)
            if at > now { planned[alert] = at }
        }
        return planned
    }

    /// Avgången går inte att ta: inget ska ligga kvar.
    public mutating func cancel(now: Date) {
        noteSent(now: now)
        planned = [:]
    }

    /// Om du ska få veta att avgången har ändrats så att du inte hinner, även när du går. En gång per avgång.
    /// `trip` är avgången som den är nu, eller nil när den inte går att ta, och då säger `lost` varför.
    /// Att du själv blev för sen är ingen ändring.
    public mutating func change(key: String, trip: Trip?, lost: FollowChange?, spot: FollowSpot, now: Date) -> FollowChange? {
        guard key == self.key, !warned, spot != .atStop else { return nil }
        var change = trip == nil ? lost : nil
        if let trip, let firstTime, trip.status == .missed {
            let moved = firstTime.timeIntervalSince(trip.time)
            // Utan ändringen hade du hunnit.
            if moved >= 60, now < trip.leaveAt.addingTimeInterval(moved) { change = .earlier }
        }
        if change != nil { warned = true }
        return change
    }

    private mutating func noteSent(now: Date) {
        for (alert, at) in planned where at <= now { sent.insert(alert) }
    }

    private mutating func retarget(_ trip: Trip) {
        guard trip.key != key else { return }
        key = trip.key
        firstTime = trip.time
        planned = [:]
        sent = []
        warned = false
    }
}

// MARK: Orden

public struct AlertWords: Equatable, Sendable {
    public var title: String
    public var body: String
}

/// Samma ord som kortet visar när notisen kommer.
public func followAlertWords(_ alert: FollowAlert, trainTime: Date, mode: Int, label: String, weather: Weather? = nil) -> AlertWords {
    let minutes = Int(alert.minutesBefore)
    return AlertWords(
        title: departureMessage(status: alert.status, minutes: minutes, trainTime: trainTime, weather: weather, label: label).title,
        body: alertBody(status: alert.status, minutes: minutes, trainTime: trainTime, mode: mode, label: label, weather: weather))
}

/// Säger rakt vad som hänt. `next` är avgången du får i stället.
public func followChangeWords(_ change: FollowChange, trainTime: Date, mode: Int, label: String, next: Trip?) -> AlertWords {
    let name = tripName(trainTime, mode: mode, label)
    let title: String
    switch change {
    case .cancelled: title = "Inställt."
    case .connectionLost: title = "Bytet spricker."
    case .earlier: title = "Den hinner du inte."
    }
    let what: String
    switch change {
    case .cancelled: what = "\(name) går inte."
    case .connectionLost: what = "Bytet efter \(name) hinns inte."
    case .earlier: what = "\(name) går tidigare än det var tänkt."
    }
    let then = next.map { " Ta \(tripName($0, label)) i stället." } ?? ""
    return AlertWords(title: title, body: what + then)
}
