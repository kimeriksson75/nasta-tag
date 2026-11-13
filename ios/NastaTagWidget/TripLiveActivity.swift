import ActivityKit
import NastaTagCore
import SwiftUI
import WidgetKit

/// Tåget på låsskärmen och i Dynamic Island, med samma ord som i appen.
/// Hela minuter i stället för en sekundräknare: iOS byter sekunderna mot streck när låsskärmen
/// är nedtonad, och minuter är det appen själv visar. Appen räknar ner dem medan du följer tåget,
/// och "Gå senast" står kvar som klockslag om appen ändå skulle hamna efter.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            LockScreenView(state: context.state, label: context.attributes.label)
                .activityBackgroundTint(Mood(context.state.status).background)
                .activitySystemActionForegroundColor(Mood(context.state.status).ink)
        } dynamicIsland: { context in
            let state = context.state
            let mood = Mood(state.status)
            let message = state.message
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.headline).font(.caption.weight(.semibold))
                        Text(message.wait).font(.title.weight(.heavy)).monospacedDigit()
                    }
                    .foregroundStyle(mood.accent)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tripName(state.trainTime, mode: state.mode, context.attributes.label)).font(.subheadline.weight(.bold))
                        Text(state.line).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
            } compactLeading: {
                Circle().fill(mood.accent).frame(width: 12, height: 12)
            } compactTrailing: {
                Text(state.status == .rush ? "nu" : message.wait).font(.caption.weight(.bold)).monospacedDigit()
            } minimal: {
                Circle().fill(mood.accent).frame(width: 12, height: 12)
            }
            .keylineTint(mood.accent)
        }
    }
}

extension TripAttributes.ContentState {
    var message: DepartureMessage { departureMessage(status: status, minutes: minutes, trainTime: trainTime) }
}

struct LockScreenView: View {
    let state: TripAttributes.ContentState
    let label: String

    var body: some View {
        let mood = Mood(state.status)
        let message = state.message
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.headline).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                    Text(message.wait)
                        .font(.system(size: 44, weight: .heavy))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(message.caption).font(.subheadline)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tripName(state.trainTime, mode: state.mode, label)).font(.headline)
                    Text(state.line).font(.subheadline)
                    Text("Från \(state.station)").font(.subheadline).foregroundStyle(mood.muted)
                    if state.status == .calm || state.status == .hurry {
                        Text("Gå senast \(stockholmClock(state.leaveBy))")
                            .font(.subheadline).foregroundStyle(mood.muted)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                if let minutes = state.snoozeMinutes, state.status != .missed {
                    Button(intent: SnoozeTripIntent()) { Pill(text: "Snooze \(minutes) min") }
                }
                Button(intent: StopFollowingIntent()) { Pill(text: "Sluta följa") }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(mood.ink)
        .fontDesign(.rounded)
        .padding(20)
    }
}

/// Knapparna på låsskärmen, lika breda och mjukt rundade.
private struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(Color(hex: "#2A2D34")))
    }
}
