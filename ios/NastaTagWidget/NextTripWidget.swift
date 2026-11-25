import CoreLocation
import NastaTagCore
import SwiftUI
import WidgetKit

/// Nästa avgång på hemskärmen och låsskärmen. Reglerna för vad som visas ligger i NastaTagCore (Glance).
struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTrip", provider: NextTripProvider()) { NextTripView(entry: $0) }
            .configurationDisplayName("Nästa tåg")
            .description("När du behöver gå för att hinna med nästa avgång.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextTripEntry: TimelineEntry {
    var date: Date
    var glance: Glance
    var label = "Hem"
    var fetchedAt: Date?
}

struct NextTripProvider: TimelineProvider {
    private static let refreshSeconds: TimeInterval = 15 * 60
    private static let retrySeconds: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> NextTripEntry { NextTripEntry(date: .now, glance: .stale) }

    func getSnapshot(in context: Context, completion: @escaping (NextTripEntry) -> Void) {
        // Widgetgalleriet visar ett exempel, aldrig en påhittad avgång på hemskärmen.
        if context.isPreview { return completion(.example) }
        Task { completion(await load().entries[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTripEntry>) -> Void) {
        Task {
            let (entries, reload) = await load()
            completion(Timeline(entries: entries, policy: .after(reload)))
        }
    }

    private func load() async -> (entries: [NextTripEntry], reload: Date) {
        let now = Date()
        func say(_ words: String, label: String = "", after seconds: TimeInterval = Self.refreshSeconds) -> ([NextTripEntry], Date) {
            ([NextTripEntry(date: now, glance: .words(words), label: label)], now.addingTimeInterval(seconds))
        }
        guard let state = SharedState.load(), !state.places.isEmpty else { return say("Öppna appen och lägg till en plats.") }
        guard let location = await WidgetLocation.current() else { return say("Öppna appen så att den vet var du är.", after: Self.retrySeconds) }
        let position = Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        let here = placeAt(state.places, position: position)
        guard let place = nextDestination(state.places, activeId: state.activeId, hereId: here, now: now, chosenId: state.chosenId),
              let target = place.coordinate else { return say("Öppna appen och välj en plats.") }
        if place.id == here { return say("Du är redan vid \(place.label).", label: place.label) }
        if state.skippedDay == skipKey(placeId: place.id, now: now) { return say("Ingen resa idag.", label: place.label) }
        do {
            async let hours = weatherHours(position)
            let journeys = try await fetchUpcomingJourneys(from: position, to: target, now: now)
            // Halka räknas som i appen, annars säger widgeten och appen olika.
            let icy = NastaTagCore.weather(at: now, hours: await hours, at: position) == .ice
            let fetchedAt = Date()
            let moments = glanceTimeline(journeys, fetchedAt: fetchedAt, positionAt: location.timestamp,
                                         walkFactor: icy ? iceWalkFactor : 1, snoozedLeaveAt: state.snoozedLeaveAt)
            let entries = moments.map { NextTripEntry(date: $0.date, glance: $0.glance, label: place.label, fetchedAt: fetchedAt) }
            return (entries, fetchedAt.addingTimeInterval(Self.refreshSeconds))
        } catch {
            return ([NextTripEntry(date: now, glance: .stale, label: place.label)], now.addingTimeInterval(Self.retrySeconds))
        }
    }

    private func weatherHours(_ position: Coordinate) async -> [WeatherHour] {
        guard let (data, _) = try? await URLSession.shared.data(from: smhiURL(position)) else { return [] }
        return (try? parseSMHI(data)) ?? []
    }
}

extension NextTripEntry {
    static var example: NextTripEntry {
        let now = Date()
        return NextTripEntry(date: now, glance: .example(now: now), label: "Hem", fetchedAt: now)
    }
}

/// Var du är, en gång. Svarar inte platsen i tid duger den senast kända; den bär sin egen ålder.
@MainActor
private final class WidgetLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    static func current() async -> CLLocation? { await WidgetLocation().ask() }

    private func ask() async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        if let known = manager.location, -known.timestamp.timeIntervalSinceNow < 60, known.horizontalAccuracy < 100 { return known }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        let timeout = Task { try? await Task.sleep(for: .seconds(6)); finish(nil) }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation = $0; manager.requestLocation() }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location ?? manager.location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

// MARK: Utseendet

struct NextTripView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextTripEntry

    private var mood: Mood {
        if case .countdown(let trip) = entry.glance { return Mood(trip.status) }
        return .idle
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Text(inline)
            default: small
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) { mood.background }
    }

    private func wait(_ trip: Trip) -> String { departureMessage(trip, label: entry.label).wait }

    @ViewBuilder private var small: some View {
        switch entry.glance {
        case .countdown(let trip):
            VStack(spacing: 8) {
                ZStack {
                    Ring(target: ringTarget(leaveAt: trip.leaveAt, mood: mood, now: entry.date), width: 8)
                    VStack(spacing: 0) {
                        Text(wait(trip)).font(.title3.weight(.heavy)).minimumScaleFactor(0.6).lineLimit(1)
                        if trip.status != .rush { Text("tills du går").font(.system(size: 9, weight: .semibold)).foregroundStyle(mood.muted) }
                    }
                    .padding(12)
                }
                tripLines(trip)
            }
            .foregroundStyle(mood.ink)
            .accessibilityElement(children: .combine)
        case .clock(let trip):
            VStack(alignment: .leading, spacing: 4) {
                Text("Nästa").font(.caption.weight(.semibold)).foregroundStyle(mood.muted)
                Text(stockholmClock(trip.time)).font(.largeTitle.weight(.heavy))
                Text("från \(trip.stop.name)").font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Text("Öppna för tid att gå").font(.caption2).foregroundStyle(mood.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(mood.ink)
        case .stale: sentence("Öppna för färska tider")
        case .words(let words): sentence(words)
        }
    }

    private func tripLines(_ trip: Trip) -> some View {
        VStack(spacing: 1) {
            Text(tripName(trip, entry.label)).font(.caption.weight(.heavy))
            Text(arrivalPhrase(entry.label, arrival: trip.arrival)).font(.caption2.weight(.semibold)).foregroundStyle(mood.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func sentence(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tram.fill").font(.title3).foregroundStyle(mood.muted)
            Spacer(minLength: 0)
            Text(words).font(.subheadline.weight(.heavy)).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(mood.ink)
    }

    @ViewBuilder private var circular: some View {
        switch entry.glance {
        case .countdown(let trip):
            Gauge(value: ringTarget(leaveAt: trip.leaveAt, mood: mood, now: entry.date).fraction) {
                Text("min")
            } currentValueLabel: {
                Text(trip.status == .rush ? "nu" : "\(minutesToLeave(trip.slackMinutes))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(trip.status == .rush ? "Gå nu" : "Gå om \(wait(trip))")
        case .clock(let trip):
            ZStack { AccessoryWidgetBackground(); Text(stockholmClock(trip.time)).font(.caption.weight(.bold)) }
        default:
            ZStack { AccessoryWidgetBackground(); Image(systemName: "tram.fill") }
                .accessibilityLabel(inline)
        }
    }

    @ViewBuilder private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.glance {
            case .countdown(let trip):
                Text(inline).font(.headline.weight(.heavy))
                Text(tripName(trip, entry.label)).font(.subheadline)
                Text(arrivalPhrase(entry.label, arrival: trip.arrival)).font(.caption)
            case .clock(let trip):
                Text(tripName(trip, entry.label)).font(.headline.weight(.heavy))
                Text("från \(trip.stop.name)").font(.subheadline)
            default:
                Text(inline).font(.headline)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: String {
        switch entry.glance {
        case .countdown(let trip): trip.status == .rush ? "Gå nu" : "Gå om \(wait(trip))"
        case .clock(let trip): tripName(trip, entry.label)
        case .stale: "Öppna för färska tider"
        case .words(let words): words
        }
    }
}

private struct Ring: View {
    let target: RingTarget
    let width: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(target.mood.track, lineWidth: width)
            Circle().trim(from: 0, to: target.fraction)
                .stroke(target.mood.accent, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
    }
}
