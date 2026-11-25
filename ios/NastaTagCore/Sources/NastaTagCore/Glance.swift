import Foundation

// Widgeten: vad den visar minut för minut mellan hämtningarna. iOS bestämmer när den får hämta nytt,
// så reglerna här handlar om att hellre säga "öppna appen" än att visa något som kanske inte stämmer.

/// Det appen delar med widgeten. Appens egna sparade platser ligger kvar där de alltid har legat.
public struct SharedState: Codable, Equatable, Sendable {
    public var places: [Place]
    public var activeId: String?
    public var chosenId: String?
    /// "jobb|2026-11-15", som i appen.
    public var skippedDay: String?
    /// När du skulle ha gått till avgången du har snoozat. Bara senare avgångar räknas.
    public var snoozedLeaveAt: Date?
    public init(places: [Place], activeId: String? = nil, chosenId: String? = nil, skippedDay: String? = nil, snoozedLeaveAt: Date? = nil) {
        self.places = places
        self.activeId = activeId
        self.chosenId = chosenId
        self.skippedDay = skippedDay
        self.snoozedLeaveAt = snoozedLeaveAt
    }

    public static let group = "group.se.medgesej.nastatag"
    private static let key = "shared"
    private static var store: UserDefaults? { UserDefaults(suiteName: group) }

    public static func load() -> SharedState? {
        store?.data(forKey: key).flatMap { try? JSONDecoder().decode(SharedState.self, from: $0) }
    }
    public func save() { Self.store?.set(try? JSONEncoder().encode(self), forKey: Self.key) }
}

/// Dagen och platsen du har struntat i, samma nyckel i appen och widgeten.
public func skipKey(placeId: String, now: Date) -> String { "\(placeId)|\(stockholmDay(now))" }

/// Så länge visas tider efter en hämtning.
public let glanceFreshSeconds: TimeInterval = 30 * 60
/// Är positionen äldre än så visas klockslaget i stället för nedräkningen: du kan ha gått någon annanstans.
public let glancePositionSeconds: TimeInterval = 10 * 60

public enum Glance: Equatable, Sendable {
    /// Minuter tills du behöver gå, som i appen.
    case countdown(Trip)
    /// Avgången utan "gå nu", när widgeten inte vet säkert var du är.
    case clock(Trip)
    /// Tiderna är för gamla, eller gick inte att hämta.
    case stale
    /// Något att säga i stället för en resa.
    case words(String)
}

public struct GlanceMoment: Equatable, Sendable {
    public var date: Date
    public var glance: Glance
}

/// Vad widgeten visar från `fetchedAt` tills tiderna är för gamla: ett ögonblick för varje minut som byts.
/// Resorna räknas om i varje ögonblick, så en avgång du inte hinner byts mot nästa utan ny hämtning.
public func glanceTimeline(_ journeys: [Journey], fetchedAt: Date, positionAt: Date,
                           walkFactor: Double = 1, snoozedLeaveAt: Date? = nil) -> [GlanceMoment] {
    let end = fetchedAt.addingTimeInterval(glanceFreshSeconds)
    let certainUntil = positionAt.addingTimeInterval(glancePositionSeconds)
    var moments: [GlanceMoment] = []
    var now = fetchedAt
    while now < end {
        let trips = buildTrips(journeys, now: now, walkFactor: walkFactor)
            .filter { trip in snoozedLeaveAt.map { trip.leaveAt > $0 } ?? true }
        guard let trip = pickTrips(trips).next else { break }
        let certain = now < certainUntil
        moments.append(GlanceMoment(date: now, glance: certain ? .countdown(trip) : .clock(trip)))
        // Nästa minutgräns. En avgång som löper ut byts strax efter, precis som i appen.
        let left = trip.leaveAt.timeIntervalSince(now)
        var step = left.truncatingRemainder(dividingBy: 60)
        if step < 0.5 { step += 60 }
        var following = now.addingTimeInterval(min(step, max(left, 0)) + 0.5)
        if certain, following > certainUntil { following = certainUntil }
        now = following
    }
    if moments.isEmpty { return [GlanceMoment(date: fetchedAt, glance: .words("Inga avgångar du hinner med just nu."))] }
    moments.append(GlanceMoment(date: min(now, end), glance: .stale))
    return moments
}

extension Glance {
    /// Exemplet i widgetgalleriet. Visas aldrig på hemskärmen.
    public static func example(now: Date) -> Glance {
        .countdown(Trip(key: "exempel", leaveAt: now.addingTimeInterval(6.5 * 60), time: now.addingTimeInterval(14 * 60),
                        arrival: now.addingTimeInterval(32 * 60), mode: 2, line: "18", towards: "Farsta strand",
                        stop: Stop(name: "T-Centralen", lat: 59.331, lon: 18.059), walkMinutes: 7.5, walkMeters: 600,
                        transfers: [], slackMinutes: 6.5, status: .calm))
    }
}
