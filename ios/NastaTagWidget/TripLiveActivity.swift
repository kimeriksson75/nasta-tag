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
            let state = context.state.shown(stale: context.isStale)
            LockScreenView(state: state, label: context.attributes.label)
                .activityBackgroundTint(Mood(state.status).background)
                .activitySystemActionForegroundColor(Mood(state.status).ink)
        } dynamicIsland: { context in
            let state = context.state.shown(stale: context.isStale)
            let mood = Mood(state.status)
            let message = state.message(label: context.attributes.label)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title).font(.caption.weight(.semibold))
                        WaitText(state: state, wait: message.wait).font(.title.weight(.heavy)).monospacedDigit()
                    }
                    .foregroundStyle(mood.accent)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.status != .missed {
                        StageBar(state: state, label: context.attributes.label, mood: mood).padding(.horizontal, 4)
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
                Group {
                    if state.boarded == true {
                        Text(stockholmClock(state.arrival ?? state.trainTime))
                    } else if state.status == .rush && state.arrived != true {
                        Text("nu")
                    } else {
                        WaitText(state: state, wait: message.wait)
                    }
                }
                .font(.caption.weight(.bold)).monospacedDigit()
                .frame(maxWidth: 44)
            } minimal: {
                Circle().fill(mood.accent).frame(width: 12, height: 12)
            }
            .keylineTint(mood.accent)
        }
    }
}

extension TripAttributes.ContentState {
    /// Har avgången gått utan att appen hunnit säga det visar kortet den som missad,
    /// med nedräkningen till nästa i stället för en tid som inte stämmer längre.
    func shown(stale: Bool) -> Self {
        guard stale, status != .missed, boarded != true, arrived != true, skipped != true else { return self }
        var missed = self
        missed.status = .missed
        missed.offerSkip = true
        missed.snoozeMinutes = nil
        missed.weather = nil
        return missed
    }

    /// När du ska gå till nästa avgång, om den inte heller har passerat.
    var upcomingLeaveBy: Date? {
        guard status == .missed, let nextLeaveBy, nextLeaveBy > .now else { return nil }
        return nextLeaveBy
    }

    func message(label: String) -> DepartureMessage {
        if boarded == true {
            return boardedMessage(trainTime: trainTime, arrival: arrival, label: label)
        }
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
            onboard(mood: mood)
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

    /// Ombord: kortet ligger kvar resan ut, med när du är framme och förloppet dit.
    private func onboard(mood: Mood) -> some View {
        let message = state.message(label: label)
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.title).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(message.wait)
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(message.caption).font(.subheadline)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tripName(state.trainTime, mode: state.mode, label)).font(.headline)
                    Text(state.line).font(.subheadline).lineLimit(1)
                    Text("Från \(state.station)").font(.subheadline).foregroundStyle(mood.muted).lineLimit(1)
                }
                .multilineTextAlignment(.trailing)
            }
            StageBar(state: state, label: label, mood: mood)
            Button(intent: StopFollowingIntent()) { Pill(text: "Sluta följa") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(mood.ink)
        .fontDesign(.rounded)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func trip(mood: Mood, message: DepartureMessage, words: SkipWords) -> some View {
        // Låsskärmen ger kortet högst 160 punkter, och blir det högre trycker iOS ihop det och
        // äter upp marginalerna. Därför står "Gå senast" i förloppet och knapparna är låga.
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.title).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                    WaitText(state: state, wait: message.wait)
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if state.upcomingLeaveBy != nil, let nextTrainTime = state.nextTrainTime {
                        Text("tills du går till \(stockholmClock(nextTrainTime))").font(.subheadline)
                    } else {
                        Text(message.caption).font(.subheadline)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tripName(state.trainTime, mode: state.mode, label)).font(.headline)
                    Text(state.line).font(.subheadline).lineLimit(1)
                    Text("Från \(state.station)").font(.subheadline).foregroundStyle(mood.muted).lineLimit(1)
                }
                .multilineTextAlignment(.trailing)
            }
            if state.status != .missed {
                StageBar(state: state, label: label, mood: mood)
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

/// Minuterna, eller när avgången är missad nedräkningen till när du ska gå till nästa.
/// iOS räknar ner den själv, så den stämmer även om appen sover.
struct WaitText: View {
    let state: TripAttributes.ContentState
    let wait: String

    var body: some View {
        if let leaveBy = state.upcomingLeaveBy {
            Text(timerInterval: Date.now...leaveBy, countsDown: true)
        } else {
            Text(wait)
        }
    }
}

/// Förloppet i skedet du är i, som en bil på väg i en taxiapp. Ändarna säger var i resan du är:
/// sängen till att gå, att gå till hållplatsen, hållplatsen till tåget och tåget till dit du ska.
/// Hemma, vid hållplatsen och ombord fylls det över tid och iOS flyttar det själv. På väg fylls det
/// efter sträckan, som appen skickar när du går.
struct StageBar: View {
    let state: TripAttributes.ContentState
    let label: String
    let mood: Mood

    var body: some View {
        let stage = state.currentStage
        let ends = stageEnds(stage, label: label, trainTime: state.trainTime, mode: state.mode)
        HStack(spacing: 8) {
            Image(systemName: ends.start)
                .font(.footnote.weight(.bold))
                .foregroundStyle(mood.muted)
            Group {
                if let interval = stageInterval(stage, leaveBy: state.leaveBy, trainTime: state.trainTime, arrival: state.arrival) {
                    ProgressView(timerInterval: interval, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                } else {
                    ProgressView(value: state.walked ?? 0)
                }
            }
            .progressViewStyle(.linear)
            .tint(mood.accent)
            HStack(spacing: 4) {
                Image(systemName: ends.end)
                if let text = endText(stage) { Text(text).monospacedDigit() }
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(mood.accent)
            // Längst ut målet och när du är där, dämpat: resten av resan, inte det du gör nu.
            // Ombord är det redan det stora på kortet.
            if stage != .onboard, let arrival = state.arrival {
                HStack(spacing: 4) {
                    Image(systemName: destinationSymbol(label: label, trainTime: state.trainTime))
                    Text(stockholmClock(arrival)).monospacedDigit()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(mood.muted)
                .padding(.leading, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(stage))
    }

    /// Klockslaget eller sträckan i änden: gå senast hemma, metrarna på väg och avgången vid hållplatsen.
    /// Ombord står tiden redan stort på kortet.
    private func endText(_ stage: TripStage) -> String? {
        switch stage {
        case .home: state.status == .calm || state.status == .hurry ? stockholmClock(state.leaveBy) : nil
        case .walking: state.metersLeft.map(metersText)
        case .atStop: stockholmClock(state.trainTime)
        case .onboard: nil
        }
    }

    private func accessibility(_ stage: TripStage) -> String {
        switch stage {
        case .home: "Gå senast \(stockholmClock(state.leaveBy))" + arrivalSuffix
        case .walking: (state.metersLeft.map { "\(metersText($0)) kvar till \(state.station)" } ?? "På väg till \(state.station)") + arrivalSuffix
        case .atStop: "Avgår \(stockholmClock(state.trainTime))" + arrivalSuffix
        case .onboard: "Framme cirka \(stockholmClock(state.arrival ?? state.trainTime))"
        }
    }

    private var arrivalSuffix: String {
        state.arrival.map { ", \(arrivalPhrase(label, arrival: $0))" } ?? ""
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
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(primary ? Mood.calm.accent : Color(hex: "#2A2D34")))
    }
}
