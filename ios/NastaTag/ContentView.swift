import NastaTagCore
import SwiftUI

/// En skärm, en sak i taget: vart du ska överst, när du ska gå i mitten,
/// vägen dit och knappen för låsskärmen nere vid tummen.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showMap = false

    private var mood: Mood { Mood(model.blocker == nil ? model.next?.status : nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Två delar luft under och en över lägger beskedet en bit ovanför mitten.
            Spacer(minLength: 24)
            hero
            Spacer(minLength: 32)
            Spacer(minLength: 0)
            bottom
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(mood.background.ignoresSafeArea())
        .foregroundStyle(mood.ink)
        .tint(mood.ink)
        .animation(.easeInOut(duration: 0.5), value: model.next?.status)
        .preferredColorScheme(mood == .hurry ? .light : .dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showMap) { WalkMapView(mood: mood) }
        .onAppear { if model.places.isEmpty { showSettings = true } }
    }

    // MARK: Överst: vart du ska

    /// Platser du kan välja: alla utom den du står vid.
    private var destinations: [Place] {
        guard let here = model.start?.station.name else { return model.places }
        return model.places.filter { $0.station != here }
    }

    private var header: some View {
        HStack {
            if let destination = model.destination {
                if destinations.count > 1 {
                    Menu {
                        ForEach(destinations) { place in
                            Button { model.choose(place) } label: {
                                if place.id == destination.id { Label(place.label, systemImage: "checkmark") } else { Text(place.label) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(destination.label)
                            Image(systemName: "chevron.down").font(.footnote.weight(.bold))
                        }
                        .font(.headline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Till \(destination.label), byt destination")
                } else {
                    Text(destination.label).font(.headline).frame(minHeight: 44)
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

    // MARK: Mitten: när du ska gå

    @ViewBuilder private var hero: some View {
        if let blocker = model.blocker {
            VStack(alignment: .leading, spacing: 20) {
                Text(blocker).font(.title.weight(.bold))
                if model.places.isEmpty {
                    Button("Lägg till plats") { showSettings = true }.buttonStyle(Outline(mood: mood))
                }
            }
        } else if let train = model.next, let destination = model.destination {
            let message = departureMessage(train)
            VStack(alignment: .leading, spacing: 0) {
                Text(message.headline).font(.title2.weight(.bold))
                Text(message.wait)
                    .font(.system(size: 104, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.vertical, -6)
                Text(message.caption).font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trainName(train.time, destination.label)).font(.title2.weight(.bold))
                    Text(lineText(train)).font(.subheadline).foregroundStyle(mood.muted)
                }
                .padding(.top, 24)
                if !model.later.isEmpty {
                    later.padding(.top, 20)
                }
            }
        }
    }

    private func lineText(_ train: Train) -> String {
        var parts = ["Linje \(train.line) mot \(train.destination)"]
        if let start = model.start { parts.append(start.station.name) }
        if let transfer = model.plan?.transfer { parts.append("byt vid \(transfer)") }
        return parts.joined(separator: " · ")
    }

    private var later: some View {
        HStack(spacing: 12) {
            Text("Senare").fontWeight(.semibold)
            Text(model.later.map { $0.time.formatted(date: .omitted, time: .shortened) }.joined(separator: " · "))
                .monospacedDigit()
                .foregroundStyle(mood.muted)
        }
        .font(.subheadline)
    }

    // MARK: Nederst: vägen dit och låsskärmen

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.blocker == nil {
                walkRow
                followButton
            }
            if let fetchedAt = model.fetchedAt {
                Text("Uppdaterad \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(mood.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// En rad som öppnar kartan: pilen pekar mot stationen när telefonen har kompass.
    @ViewBuilder private var walkRow: some View {
        if let start = model.start {
            let minutes = "\(start.estimated ? "ca " : "")\(max(1, Int(start.walkMinutes.rounded()))) min"
            Button { showMap = true } label: {
                HStack(spacing: 12) {
                    Group {
                        if let angle = model.arrowAngle {
                            Image(systemName: "location.north.fill")
                                .rotationEffect(.degrees(angle))
                                .animation(.easeOut(duration: 0.2), value: angle)
                        } else {
                            Image(systemName: "figure.walk")
                        }
                    }
                    .font(.title2)
                    .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.stationDistance.map { "\(distanceText($0)) · \(minutes)" } ?? "Du är vid stationen")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text("till \(start.station.name)").font(.subheadline).foregroundStyle(mood.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(mood.muted)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.stationDistance.map(distanceText) ?? "") till \(start.station.name), visa gångvägen på kartan")
            .overlay(alignment: .top) { Rectangle().fill(mood.ink.opacity(0.2)).frame(height: 1) }
        }
    }

    @ViewBuilder private var followButton: some View {
        if model.following != nil {
            Button("Sluta följa") { model.unfollow() }.buttonStyle(Outline(mood: mood, wide: true))
        } else if model.canFollow {
            Button("Följ på låsskärmen") { model.follow() }.buttonStyle(Filled(mood: mood))
        }
    }
}

struct Outline: ButtonStyle {
    let mood: Mood
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 52)
            .overlay(Capsule().stroke(mood.ink.opacity(0.4)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Huvudknappen: fylld i textfärgen, så den syns i alla lägen.
struct Filled: ButtonStyle {
    let mood: Mood
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(mood.background)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(mood.ink))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
