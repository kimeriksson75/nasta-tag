import ActivityKit
import AppIntents
import NastaTagCore

/// Knapparna på låsskärmen. De körs i appen, som har resorna, och appen kopplar in vad de gör.
@MainActor
enum TripActions {
    static var snooze: (() -> Void)?
    static var stopFollowing: (() -> Void)?
}

/// Hoppa över avgången du följer och ta nästa.
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
            for activity in Activity<TripAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return .result()
    }
}
