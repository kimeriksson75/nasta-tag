import NastaTagCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showMap = false

    private var mood: Mood { Mood(model.blocker == nil ? model.next?.status : nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 24)
            hero
            Spacer(minLength: 24)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(model.choices) { place in
                Button(place.label) { model.choose(place) }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .overlay(Capsule().stroke(mood.ink.opacity(0.35)))
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
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

    @ViewBuilder private var hero: some View {
        if let blocker = model.blocker {
            VStack(alignment: .leading, spacing: 16) {
                Text(blocker).font(.title2.weight(.bold))
                if model.places.isEmpty {
                    Button("Lägg till plats") { showSettings = true }.buttonStyle(Outline(mood: mood))
                }
            }
        } else if let train = model.next, let destination = model.destination {
            let message = departureMessage(train)
            VStack(alignment: .leading, spacing: 6) {
                Text(message.lead).font(.title2.weight(.bold))
                Text(message.wait)
                    .font(.system(size: 96, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(message.bridge).font(.title3)
                Text("\(train.time.formatted(date: .omitted, time: .shortened))-tåget \(tripPhrase(destination.label))")
                    .font(.title2.weight(.bold))
                Text("Linje \(train.line) mot \(train.destination)").font(.subheadline).foregroundStyle(mood.muted)
                followButton.padding(.top, 18)
                if !model.later.isEmpty { laterList.padding(.top, 28) }
            }
        }
    }

    @ViewBuilder private var followButton: some View {
        if model.following != nil {
            Button("Sluta följa") { model.unfollow() }.buttonStyle(Outline(mood: mood))
        } else if model.canFollow {
            Button("Följ på låsskärmen") { model.follow() }.buttonStyle(Outline(mood: mood))
        }
    }

    private var laterList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nästa tåg").font(.subheadline.weight(.bold))
            ForEach(model.later) { train in
                HStack(spacing: 12) {
                    Text(train.time.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    Text("Linje \(train.line) mot \(train.destination)")
                }
                .font(.subheadline)
                .foregroundStyle(mood.muted)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let distance = model.stationDistance, model.blocker == nil {
                Button { showMap = true } label: {
                    HStack(spacing: 12) {
                        Text(distanceText(distance))
                            .font(.system(size: 44, weight: .heavy))
                            .monospacedDigit()
                        if let angle = model.arrowAngle {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 40))
                                .rotationEffect(.degrees(angle))
                                .animation(.easeOut(duration: 0.2), value: angle)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(distanceText(distance)) till stationen, visa gångvägen på kartan")
            }
            if let route = model.routeText {
                Text(route).font(.subheadline.weight(.semibold))
            }
            if let fetchedAt = model.fetchedAt {
                Text("Uppdaterad \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(mood.muted)
            }
        }
    }
}

struct Outline: ButtonStyle {
    let mood: Mood
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(mood.ink.opacity(0.4)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
