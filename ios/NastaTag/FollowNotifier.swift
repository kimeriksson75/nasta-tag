import Foundation
import NastaTagCore
import UserNotifications

/// Schemalägger den följda resans notiser i telefonen, så att de kommer i tid även om appen sover.
/// Vad som ska komma bestäms av FollowAlerts i NastaTagCore.
@MainActor
final class FollowNotifier {
    private(set) var alerts: FollowAlerts
    /// Om notiser är tillåtna. Nej eller inte svarat: Följ fungerar som förut, med larm från kortet.
    private(set) var allowed = false

    /// Det som ligger schemalagt, så att samma notis inte läggs om varje tick.
    private var pending: [FollowAlert: (at: Date, words: AlertWords)] = [:]
    private let center = UNUserNotificationCenter.current()
    private static let key = "followAlerts"

    init() {
        alerts = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(FollowAlerts.self, from: $0) } ?? FollowAlerts()
    }

    /// Frågar första gången, efter det svarar iOS direkt.
    func askPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await checkPermission()
    }

    func checkPermission() async {
        allowed = await center.notificationSettings().authorizationStatus == .authorized
    }

    func plan(_ trip: Trip, spot: FollowSpot, now: Date, words: (FollowAlert) -> AlertWords) {
        let times = update { $0.plan(trip, spot: spot, now: now) }
        let wasPending = !pending.isEmpty
        for alert in FollowAlert.allCases {
            guard allowed, let at = times[alert] else {
                // En notis som har kommit ligger kvar att läsa, tills du har gått.
                if pending.removeValue(forKey: alert) != nil { center.removePendingNotificationRequests(withIdentifiers: [alert.id]) }
                continue
            }
            let words = words(alert)
            if let old = pending[alert], old.at == at, old.words == words { continue }
            pending[alert] = (at, words)
            let wait = max(1, at.timeIntervalSinceNow)
            add(alert.id, words, trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
        }
        // Efter en omstart vet appen inte vad som ligger kvar, så det rensas när inget ska ligga där.
        if times.isEmpty, wasPending || !cleaned {
            cleaned = true
            cancelPending()
        }
        if alerts.left { center.removeDeliveredNotifications(withIdentifiers: FollowAlert.allCases.map(\.id)) }
        if !times.isEmpty { cleaned = false }
    }
    private var cleaned = false

    /// Avgången går inte att ta: inget ska ligga kvar.
    func cancel(now: Date) {
        update { $0.cancel(now: now) }
        cancelPending()
    }

    func change(key: String, trip: Trip?, lost: FollowChange?, spot: FollowSpot, now: Date) -> FollowChange? {
        update { $0.change(key: key, trip: trip, lost: lost, spot: spot, now: now) }
    }

    func tellChange(_ words: AlertWords) {
        add(FollowAlert.changeId, words, trigger: nil)
    }

    /// Du följer ingen resa: allt tas bort och glöms.
    func clear() {
        alerts = FollowAlerts()
        pending = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
        removeFollowAlerts()
    }

    private func cancelPending() {
        pending = [:]
        center.removePendingNotificationRequests(withIdentifiers: FollowAlert.allCases.map(\.id))
    }

    private func add(_ id: String, _ words: AlertWords, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = words.title
        content.body = words.body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    @discardableResult
    private func update<T>(_ change: (inout FollowAlerts) -> T) -> T {
        let before = alerts
        let result = change(&alerts)
        if alerts != before { UserDefaults.standard.set(try? JSONEncoder().encode(alerts), forKey: Self.key) }
        return result
    }
}
