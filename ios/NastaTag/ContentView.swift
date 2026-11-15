import NastaTagCore
import SwiftUI

/// Ring A: vart du ska överst, ringen som räknar ner i mitten, och nere vid tummen
/// vägen dit, Snooze och knappen för låsskärmen.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showMap = false
    @State private var askSkip = false

    private var mood: Mood {
        Mood(model.blocker == nil && !model.isSkipped && model.missed == nil ? model.next?.status : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            hero
            Spacer(minLength: 24)
            bottom
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mood.background.ignoresSafeArea())
        .foregroundStyle(mood.ink)
        .tint(mood.ink)
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.5), value: model.next?.status)
        .preferredColorScheme(.dark)
        .overlay { skipDialog }
        .animation(.easeOut(duration: 0.2), value: askSkip)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showMap) { WalkMapView(mood: mood) }
        .onAppear { if model.places.isEmpty { showSettings = true } }
    }

    // MARK: Överst: vart du ska

    private var header: some View {
        HStack {
            if let destination = model.destination {
                if model.destinations.count > 1 {
                    Menu {
                        ForEach(model.destinations) { place in
                            Button { model.choose(place) } label: {
                                if place.id == destination.id { Label(place.label, systemImage: "checkmark") } else { Text(place.label) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(destination.label)
                            Image(systemName: "chevron.down").font(.footnote.weight(.bold))
                        }
                        .font(.headline.weight(.heavy))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Till \(destination.label), byt destination")
                } else {
                    Text(destination.label).font(.headline.weight(.heavy)).frame(minHeight: 44)
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inställningar")
        }
    }

    // MARK: Mitten: ringen

    @ViewBuilder private var hero: some View {
        if model.isSkipped, let destination = model.destination {
            VStack(spacing: 12) {
                Text(model.skipDone ?? "Okej. Vi hörs imorgon.").font(.title2.weight(.heavy))
                Text("Inga påminnelser om resan \(tripPhrase(destination.label)) idag.")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(mood.muted)
                Button("Visa avgångar igen") { model.unskip() }
                    .buttonStyle(Outline(mood: mood))
                    .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } else if model.blocker == nil, let missed = model.missed, let destination = model.destination {
            missedView(missed.trip, until: missed.until, destination: destination)
        } else if let blocker = model.blocker {
            VStack(spacing: 20) {
                Text(blocker).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                if model.places.isEmpty {
                    Button("Lägg till plats") { showSettings = true }.buttonStyle(Outline(mood: mood))
                }
            }
            .frame(maxWidth: .infinity)
        } else if let trip = model.next, let destination = model.destination {
            let message = departureMessage(trip)
            VStack(spacing: 0) {
                Text(message.headline)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(mood.accent)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                Ring(trip: trip, wait: message.wait, caption: message.caption, mood: mood)
                    .frame(maxWidth: 280)
                    .padding(.top, 32)
                    .padding(.bottom, 28)
                // Allt under ringen har fast höjd, så att ringen står still när resan byts.
                Text(tripName(trip, destination.label))
                    .font(.title2.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                Text(lineText(trip))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mood.muted)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
                    .padding(.top, 4)
                Group {
                if let skipped = model.snoozed {
                    Button("Ångra snooze") { model.toggleSnooze() }
                        .buttonStyle(SnoozeToggle(mood: mood, on: true))
                        .accessibilityLabel("Ångra snooze, ta \(stockholmClock(skipped.time)) igen")
                } else if let minutes = model.snoozeMinutes {
                    Button("Snooze \(minutes) min") { model.toggleSnooze() }
                        .buttonStyle(SnoozeToggle(mood: mood, on: false))
                        .accessibilityHint("Hoppa över den här avgången och ta nästa")
                } else {
                    Color.clear
                }
                }
                .frame(height: SnoozeToggle.height)
                .padding(.top, 12)
                skipLink
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            // Orden tonar över när de byts. Själva platserna ändras aldrig, så inget flyttar sig.
            .animation(.easeInOut(duration: 0.35), value: message)
            .animation(.easeInOut(duration: 0.35), value: trip.key)
        }
    }

    /// Knappen som struntar i resan. Rutan frågar först.
    private func skipButton(_ words: SkipWords) -> some View {
        Button(words.button) { askSkip = true }
            .buttonStyle(SnoozeToggle(mood: mood, on: false))
            .accessibilityLabel("Strunta i resan idag")
            .accessibilityHint("Frågar först. Sedan slutar appen påminna dig om resan idag.")
    }

    /// Den tysta vägen ut, som alltid finns: samma fråga som knappen.
    private var skipLink: some View {
        Button("Strunta i resan idag") { askSkip = true }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(mood.muted)
            .buttonStyle(.plain)
            .frame(height: Self.linkHeight)
            .contentShape(Rectangle())
            .accessibilityHint("Frågar först. Sedan slutar appen påminna dig om resan idag.")
    }

    private static let linkHeight: CGFloat = 36

    /// Frågan innan appen struntar i resan. En egen ruta, så att Ja står till vänster i grönt
    /// och Nej bredvid som en tunn knapp: det ska synas direkt vilken som är vilken.
    @ViewBuilder private var skipDialog: some View {
        if askSkip, let words = model.skipWords {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { askSkip = false }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(words.ask).font(.title3.weight(.heavy))
                        Text(words.detail).font(.subheadline).foregroundStyle(Mood.idle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Button(Voice.skipConfirm) {
                            askSkip = false
                            model.skipToday()
                        }
                        .buttonStyle(DialogButton(primary: true))
                        .accessibilityLabel("Ja, strunta i resan idag")
                        Button(Voice.skipCancel) { askSkip = false }
                            .buttonStyle(DialogButton(primary: false))
                            .accessibilityLabel("Nej, påminn mig som vanligt")
                    }
                }
                .multilineTextAlignment(.leading)
                .foregroundStyle(Mood.idle.ink)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 28).fill(Color(hex: "#1B1D22")))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Mood.idle.line, lineWidth: 1))
                .padding(.horizontal, 28)
                .accessibilityAddTraits(.isModal)
            }
            .transition(.opacity)
        }
    }

    /// Tiden att gå tog slut: en stund i grått med frågan om du bryr dig, sedan nästa avgång av sig själv.
    private func missedView(_ trip: Trip, until: Date, destination: Place) -> some View {
        let message = departureMessage(status: .missed, minutes: 0, trainTime: trip.time)
        return VStack(spacing: 0) {
            Text(message.headline)
                .font(.title2.weight(.heavy))
                .foregroundStyle(mood.accent)
                .frame(maxWidth: .infinity)
            Ring(trip: trip, wait: message.wait, caption: message.caption, mood: .idle)
                .frame(maxWidth: 280)
                .padding(.top, 32)
                .padding(.bottom, 28)
            Text(tripName(trip, destination.label))
                .font(.title2.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Button { model.dismissMissed() } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(until.timeIntervalSince(context.date).rounded(.up)))
                    Text("Nästa avgång om \(seconds) s")
                        .monospacedDigit()
                        // Samma höjd som linjeraden, så att ringen står kvar på samma plats.
                        .lineLimit(2, reservesSpace: true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mood.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Visa nästa avgång nu")
            .padding(.top, 4)
            Group {
                if let words = model.skipWords { skipButton(words) } else { Color.clear }
            }
            .frame(height: SnoozeToggle.height)
            .padding(.top, 12)
            // Länken har sin plats även här, så att inget flyttar sig.
            Color.clear.frame(height: Self.linkHeight)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        // Går vidare på sekunden, utan att vänta på nästa tick.
        .task(id: trip.key) {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            if !askSkip { model.dismissMissed() }
        }
    }

    private func lineText(_ trip: Trip) -> String {
        ([trip.lineText, "från \(trip.stop.name)"] + trip.transfers.map { "byte \($0)" }).joined(separator: " · ")
    }

    // MARK: Nederst: vägen dit, Snooze och låsskärmen

    private var bottom: some View {
        VStack(spacing: 12) {
            if model.blocker == nil && !model.isSkipped {
                // När avgången är missad finns kortet och knappen kvar men syns inte,
                // så att de tar exakt samma plats som vanligt och inget hoppar.
                let hidden = model.missed != nil
                Group {
                    walkCard
                    followButton
                }
                .opacity(hidden ? 0 : 1)
                .allowsHitTesting(!hidden)
                .accessibilityHidden(hidden)
            }
            if let fetchedAt = model.fetchedAt {
                Text("Uppdaterad \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(mood.muted)
            }
        }
    }

    /// Kortet som öppnar kartan: ursprungspilen pekar mot stationen när telefonen har kompass.
    @ViewBuilder private var walkCard: some View {
        if let trip = model.next {
            let minutes = "\(max(1, Int(trip.walkMinutes.rounded()))) min"
            Button { showMap = true } label: {
                HStack(spacing: 14) {
                    Group {
                        if let angle = model.arrowAngle {
                            Arrow()
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(angle))
                                .animation(.easeOut(duration: 0.2), value: angle)
                        } else {
                            Image(systemName: "figure.walk").font(.title2)
                        }
                    }
                    .foregroundStyle(mood.accent)
                    .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.stopDistance.map { "\(distanceText($0)) · \(minutes)" } ?? "Du är vid hållplatsen")
                            .font(.headline.weight(.heavy))
                            .monospacedDigit()
                        Text("till \(trip.stop.name) · visa vägen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(mood.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Card.height)
                .background(RoundedRectangle(cornerRadius: Card.radius).fill(mood.card))
                .overlay(RoundedRectangle(cornerRadius: Card.radius).stroke(mood.line, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: Card.radius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.stopDistance.map(distanceText) ?? "") till \(trip.stop.name), visa gångvägen på kartan")
        }
    }

    @ViewBuilder private var followButton: some View {
        if model.following != nil {
            Button("Sluta följa") { model.unfollow() }.buttonStyle(Card(mood: mood, wide: true))
        } else if model.canFollow {
            Button("Följ på låsskärmen") { model.follow() }.buttonStyle(Filled(mood: mood))
        }
    }
}

/// Ursprungspilen, samma form som på webben och på kartan.
struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width / 24, y = rect.height / 24
        var path = Path()
        path.move(to: CGPoint(x: 12 * x, y: 2 * y))
        path.addLine(to: CGPoint(x: 4.5 * x, y: 21 * y))
        path.addLine(to: CGPoint(x: 12 * x, y: 17 * y))
        path.addLine(to: CGPoint(x: 19.5 * x, y: 21 * y))
        path.closeSubpath()
        return path
    }
}

/// Kortet och knapparna under det delar höjd och rundning.
struct Card: ButtonStyle {
    static let height: CGFloat = 64
    static let radius: CGFloat = 20
    let mood: Mood
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: Self.height)
            .overlay(RoundedRectangle(cornerRadius: Self.radius).stroke(mood.line, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Self.radius))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct Outline: ButtonStyle {
    let mood: Mood
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 52)
            .overlay(Capsule().stroke(mood.line, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Snooze och Ångra snooze är samma knapp: lika stor och rund, ifylld när den är på.
struct SnoozeToggle: ButtonStyle {
    static let height: CGFloat = 52
    let mood: Mood
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .lineLimit(1)
            .frame(width: 180, height: Self.height)
            .background(Capsule().fill(on ? mood.track : .clear))
            .overlay(Capsule().stroke(mood.line, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Knapparna i frågan om att strunta i resan: Ja är fylld och grön, Nej bara en kant.
struct DialogButton: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .lineLimit(1)
            .foregroundStyle(primary ? Mood.calm.background : Mood.idle.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(primary ? Mood.calm.accent : .clear))
            .overlay(Capsule().stroke(primary ? .clear : Mood.idle.line, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Huvudknappen: fylld i lägets färg med mörk text.
struct Filled: ButtonStyle {
    let mood: Mood
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(mood.background)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Card.height)
            .background(RoundedRectangle(cornerRadius: Card.radius).fill(mood.accent))
            .contentShape(RoundedRectangle(cornerRadius: Card.radius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
