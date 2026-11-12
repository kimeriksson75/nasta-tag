import ActivityKit
import NastaTagCore
import SwiftUI
import WidgetKit

/// Tåget på låsskärmen och i Dynamic Island. Nedräkningen tickar av sig själv,
/// färgen byts när appen skickar ett nytt läge.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { context in
            LockScreenView(state: context.state, label: context.attributes.label)
                .activityBackgroundTint(Mood(context.state.status).background)
                .activitySystemActionForegroundColor(Mood(context.state.status).ink)
        } dynamicIsland: { context in
            let state = context.state
            let mood = Mood(state.status)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Lead(status: state.status).font(.caption.weight(.semibold))
                        LeaveIn(state: state).font(.title.weight(.heavy))
                    }
                    .foregroundStyle(mood == .idle ? .white : mood.background)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(trainName(state, context.attributes.label)).font(.subheadline.weight(.bold))
                        Text("Linje \(state.line) mot \(state.towards)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
            } compactLeading: {
                Circle().fill(mood.background).frame(width: 12, height: 12)
            } compactTrailing: {
                LeaveIn(state: state).font(.caption.weight(.bold)).frame(maxWidth: 44)
            } minimal: {
                Circle().fill(mood.background).frame(width: 12, height: 12)
            }
            .keylineTint(mood.background)
        }
    }
}

private func trainName(_ state: TripAttributes.ContentState, _ label: String) -> String {
    "\(state.trainTime.formatted(date: .omitted, time: .shortened))-tåget \(tripPhrase(label))"
}

/// Tiden kvar tills du måste gå. Räknar ner av sig själv, även när appen inte kör.
/// På den nedtonade låsskärmen (Alltid på) ritas skärmen bara om ungefär en gång i minuten
/// och iOS byter då sekunderna mot streck. Där visas i stället klockslaget du ska gå.
struct LeaveIn: View {
    let state: TripAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        if state.status == .missed {
            Text("–")
        } else if state.status == .rush || state.leaveBy <= .now {
            Text("nu")
        } else if dimmed {
            Text(state.leaveBy.formatted(date: .omitted, time: .shortened)).monospacedDigit()
        } else {
            Text(timerInterval: Date.now...state.leaveBy, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        }
    }
}

/// "Gå om" passar nedräkningen, "Gå kl" klockslaget på den nedtonade skärmen.
struct Lead: View {
    let status: Status
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        Text(dimmed && (status == .calm || status == .hurry) ? activityLead(status).replacingOccurrences(of: "gå om", with: "gå kl")
                .replacingOccurrences(of: "Gå om", with: "Gå kl") : activityLead(status))
    }
}

struct LockScreenView: View {
    let state: TripAttributes.ContentState
    let label: String
    var body: some View {
        let mood = Mood(state.status)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Lead(status: state.status).font(.headline)
                LeaveIn(state: state).font(.system(size: 44, weight: .heavy))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(trainName(state, label)).font(.headline)
                Text("Linje \(state.line) mot \(state.towards)").font(.subheadline)
                Text("Från \(state.station)").font(.subheadline).foregroundStyle(mood.muted)
            }
            .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(mood.ink)
        .padding(20)
    }
}
