import ActivityKit
import AppIntents
import NastaTagCore
import UserNotifications

/// Knapparna på låsskärmen. De körs i appen, som har resorna, och appen kopplar in vad de gör.
@MainActor
enum TripActions {
    static var snooze: (() -> Void)?
    static var stopFollowing: (() -> Void)?
    static var askSkip: (() -> Void)?
    static var answerSkip: ((Bool) -> Void)?
}

/// Tar bort den följda resans notiser, schemalagda och levererade.
func removeFollowAlerts() {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: FollowAlert.allIds)
    center.removeDeliveredNotifications(withIdentifiers: FollowAlert.allIds)
}

/// "Fuck it." på låsskärmen när avgången är missad: frågar först, som rutan i appen.
struct AskSkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Strunta i resan idag"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TripActions.askSkip?()
        return .result()
    }
}

/// Svaret på frågan: Ja! eller Nej 🙁.
struct AnswerSkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Svara på frågan"
    static let isDiscoverable = false

    @Parameter(title: "Strunta i resan") var skip: Bool

    init() {}
    init(skip: Bool) { self.skip = skip }

    @MainActor
    func perform() async throws -> some IntentResult {
        TripActions.answerSkip?(skip)
        return .result()
    }
}

/// Hoppa över avgången du följer och ta nästa, eller ångra det.
struct SnoozeTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TripActions.snooze?()
        return .result()
    }
}

/// Sluta visa resan på låsskärmen.
struct StopFollowingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Sluta följa"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        if let stop = TripActions.stopFollowing {
            stop()
        } else {
            // Appen har inte hunnit starta på riktigt: ta bort resan ändå.
            removeFollowAlerts()
            for activity in Activity<TripAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return .result()
    }
}
