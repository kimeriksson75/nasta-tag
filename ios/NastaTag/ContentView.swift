import NastaTagCore
import SwiftUI

/// Ring A: vart du ska överst, ringen som räknar ner i mitten, och nere vid tummen
/// vägen dit, Snooze och knappen för låsskärmen.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showMap = false

    private var mood: Mood { Mood(model.blocker == nil ? model.next?.status : nil) }

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
        if let blocker = model.blocker {
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
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            // Orden tonar över när de byts. Själva platserna ändras aldrig, så inget flyttar sig.
            .animation(.easeInOut(duration: 0.35), value: message)
            .animation(.easeInOut(duration: 0.35), value: trip.key)
        }
    }

    private func lineText(_ trip: Trip) -> String {
        ([trip.lineText, "från \(trip.stop.name)"] + trip.transfers.map { "byte \($0)" }).joined(separator: " · ")
    }

    // MARK: Nederst: vägen dit, Snooze och låsskärmen

    private var bottom: some View {
        VStack(spacing: 12) {
            if model.blocker == nil {
                walkCard
                followButton
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
