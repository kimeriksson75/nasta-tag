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
            let message = state.message(label: context.attributes.label)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title).font(.caption.weight(.semibold))
                        Text(message.wait).font(.title.weight(.heavy)).monospacedDigit()
                    }
                    .foregroundStyle(mood.accent)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.status != .missed {
                        LeaveBar(state: state, mood: mood).padding(.horizontal, 4)
                    }
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
                Text(state.status == .rush && state.arrived != true ? "nu" : message.wait).font(.caption.weight(.bold)).monospacedDigit()
            } minimal: {
                Circle().fill(mood.accent).frame(width: 12, height: 12)
            }
            .keylineTint(mood.accent)
        }
    }
}

extension TripAttributes.ContentState {
    func message(label: String) -> DepartureMessage {
        if arrived == true { return arrivedMessage(minutes: minutes, trainTime: trainTime) }
        return departureMessage(status: status, minutes: minutes, trainTime: trainTime, weather: weather, label: label)
    }
}

struct LockScreenView: View {
    let state: TripAttributes.ContentState
    let label: String

    var body: some View {
        let mood = Mood(state.status)
        let message = state.message(label: label)
        let words = skipWords(label: label, trainTime: state.trainTime, mode: state.mode)
        if state.boarded == true {
            // Tåget gick med dig: trevlig resa, en stund innan låsskärmen släpper.
            VStack(alignment: .leading, spacing: 4) {
                Text(boardedHeadline(trainTime: state.trainTime, label: label)).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                Text("Med \(tripName(state.trainTime, mode: state.mode, label)).").font(.subheadline).foregroundStyle(mood.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(mood.ink)
            .fontDesign(.rounded)
            .padding(20)
        } else if state.skipped == true {
            // Efter Ja!: samma ord som i appen, en stund innan resan försvinner.
            VStack(alignment: .leading, spacing: 4) {
                Text(words.done).font(.headline.weight(.heavy))
                Text("Inga påminnelser om resan \(tripPhrase(label)) idag.").font(.subheadline).foregroundStyle(Mood.idle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Mood.idle.ink)
            .fontDesign(.rounded)
            .padding(20)
        } else if state.askingSkip == true {
            // Rutan från appen, på låsskärmen.
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(words.ask).font(.headline.weight(.heavy))
                    Text(words.detail).font(.subheadline).foregroundStyle(mood.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Samma två svar som i appen: Ja (grön, till vänster) struntar i resan idag, Nej ångrar sig.
                HStack(spacing: 8) {
                    Button(intent: AnswerSkipIntent(skip: true)) { Pill(text: Voice.skipConfirm, primary: true) }
                    Button(intent: AnswerSkipIntent(skip: false)) { Pill(text: Voice.skipCancel) }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(mood.ink)
            .fontDesign(.rounded)
            .padding(20)
        } else {
            trip(mood: mood, message: message, words: words)
        }
    }

    private func trip(mood: Mood, message: DepartureMessage, words: SkipWords) -> some View {
        // Låsskärmen ger kortet en begränsad höjd, så avstånden är snålare här än i rutorna ovan.
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.title).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                    Text(message.wait)
                        .font(.system(size: 36, weight: .heavy))
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
                    if state.arrived != true && (state.status == .calm || state.status == .hurry) {
                        Text("Gå senast \(stockholmClock(state.leaveBy))")
                            .font(.subheadline).foregroundStyle(mood.muted)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            if state.status != .missed {
                LeaveBar(state: state, mood: mood)
            }
            HStack(spacing: 8) {
                if state.status == .missed {
                    Button(intent: AskSkipIntent()) { Pill(text: words.button) }
                        .accessibilityLabel("Strunta i resan idag")
                } else if state.snoozed == true {
                    Button(intent: SnoozeTripIntent()) { Pill(text: "Ångra snooze") }
                } else if let minutes = state.snoozeMinutes, state.status != .missed {
                    Button(intent: SnoozeTripIntent()) { Pill(text: "Snooze \(minutes) min") }
                }
                // Stänger bara låsskärmen, som i appen. Att strunta i resan frågar "Fuck it." om.
                Button(intent: StopFollowingIntent()) { Pill(text: "Sluta följa") }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(mood.ink)
        .fontDesign(.rounded)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Förloppet fram till att du ska gå, som en bil på väg i en taxiapp. Det fylls de sista
/// femton minuterna, samma tid som ringen i appen töms på, och iOS flyttar det själv utan
/// att appen behöver skicka något. Vid hållplatsen fylls det fram till avgången, med tåget i änden.
struct LeaveBar: View {
    let state: TripAttributes.ContentState
    let mood: Mood

    var body: some View {
        let end = state.arrived == true ? state.trainTime : state.leaveBy
        let start = end.addingTimeInterval(-ringFullMinutes * 60)
        HStack(spacing: 10) {
            ProgressView(timerInterval: start...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(mood.accent)
            Image(systemName: state.arrived == true ? Mode(state.mode).symbol : "figure.walk")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(mood.accent)
        }
        .accessibilityHidden(true)
    }
}

/// Knapparna på låsskärmen, lika breda och mjukt rundade.
private struct Pill: View {
    let text: String
    var primary = false
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(primary ? Mood.calm.background : Mood.idle.ink)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Capsule().fill(primary ? Mood.calm.accent : Color(hex: "#2A2D34")))
    }
}
