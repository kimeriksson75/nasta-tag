import MapKit
import NastaTagCore
import SwiftUI

/// Gångvägen till stationen i första person: du står i mitten som en pil
/// och kartan vrids med kompassen, så det du har framför dig är uppåt.
struct WalkMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mood: Mood

    @State private var camera: MapCameraPosition = .automatic
    @State private var distance: Double = 1600 // meter från kameran, ändras när du nyper

    private var route: Color { mood == .idle ? .white : mood.background }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera, interactionModes: [.zoom]) {
                if let line = model.walkRoute?.polyline {
                    MapPolyline(line).stroke(route, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                if let station = model.start?.station {
                    Annotation(station.name, coordinate: .init(latitude: station.lat, longitude: station.lon)) {
                        Circle().fill(route).stroke(mood.ink, lineWidth: 3).frame(width: 18, height: 18)
                    }
                }
                if let position = model.position {
                    Annotation("", coordinate: .init(latitude: position.lat, longitude: position.lon), anchor: .center) {
                        me
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { }
            .overlay { mood.background.opacity(0.12).allowsHitTesting(false) }
            .onMapCameraChange(frequency: .onEnd) { context in distance = context.camera.distance }
            .ignoresSafeArea()

            header
        }
        .preferredColorScheme(mood == .hurry ? .light : .dark)
        .onAppear(perform: follow)
        .onChange(of: model.heading) { follow() }
        .onChange(of: model.position) {
            follow()
            Task { await model.loadWalkRoute() }
        }
        .task { await model.loadWalkRoute() }
    }

    /// Pilen pekar alltid uppåt: kartan vrids i stället.
    private var me: some View {
        Image(systemName: model.heading == nil ? "circle.fill" : "location.north.fill")
            .font(.system(size: model.heading == nil ? 20 : 40, weight: .bold))
            .foregroundStyle(mood.ink)
            .shadow(color: .black.opacity(0.35), radius: 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let meters = model.stationDistance {
                Text(distanceText(meters))
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
            }
            if let station = model.start?.station.name {
                Text(station).font(.headline).lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stäng kartan")
        }
        .foregroundStyle(mood.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(mood.background.ignoresSafeArea(edges: .top))
    }

    private func follow() {
        guard let position = model.position else { return }
        camera = .camera(MapCamera(centerCoordinate: .init(latitude: position.lat, longitude: position.lon),
                                   distance: distance, heading: model.heading ?? 0, pitch: 30))
    }
}
