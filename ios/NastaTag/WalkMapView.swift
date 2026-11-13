import MapKit
import MapLibre
import NastaTagCore
import SwiftUI

/// Gångvägen till stationen i första person: du står i mitten som en pil
/// och kartan vrids med kompassen, så det du har framför dig är uppåt.
/// Samma karta som på webben: OpenFreeMap, målad i appens färg för läget.
struct WalkMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mood: Mood

    var body: some View {
        let theme = MapTheme(mood)
        ZStack {
            WalkMap(theme: theme, position: model.position, heading: model.heading,
                    route: model.walkRoute?.polyline.coordinates ?? [], station: model.stop)
                .overlay { Arrow().fill(theme.route).stroke(theme.halo, lineWidth: 2).frame(width: 36, height: 36) }
                .ignoresSafeArea()
            VStack {
                ringChip
                Spacer()
                walkCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(mood.background)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onChange(of: model.position) { Task { await model.loadWalkRoute() } }
        .task { await model.loadWalkRoute() }
    }

    /// Ringen flyter överst, så att du ser hur bråttom det är medan du går.
    @ViewBuilder private var ringChip: some View {
        HStack(spacing: 14) {
            if let trip = model.next, let destination = model.destination {
                let message = departureMessage(trip)
                MiniRing(mood: mood, fraction: min(1, max(0.04, trip.slackMinutes / 15)),
                         text: trip.status == .rush ? "Nu" : "\(minutesToLeave(trip.slackMinutes))")
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.headline).font(.headline.weight(.heavy)).foregroundStyle(mood.accent)
                    Text(tripName(trip, destination.label)).font(.subheadline.weight(.semibold)).foregroundStyle(mood.muted)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline.weight(.heavy))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(mood.track))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stäng kartan")
        }
        .foregroundStyle(mood.ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 32).fill(mood.background.opacity(0.92)))
    }

    /// Hur långt det är kvar, nere vid tummen.
    @ViewBuilder private var walkCard: some View {
        if let station = model.stop?.name {
            HStack(spacing: 12) {
                Arrow().fill(mood.background).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.stopDistance.map(distanceText) ?? "Du är framme")
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                    Text("till \(station)").font(.subheadline.weight(.semibold)).opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(mood.background)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 26).fill(mood.ink))
        }
    }
}

private struct MiniRing: View {
    let mood: Mood
    let fraction: Double
    let text: String

    var body: some View {
        ZStack {
            Circle().stroke(mood.track, lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(mood.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text).font(.headline.weight(.black)).monospacedDigit()
        }
        .frame(width: 56, height: 56)
    }
}

/// Webbens kartfärger, ett set per läge.
struct MapTheme: Equatable {
    var land, park, water, building, road, label, routeHex, haloHex: String

    /// Mörk karta i alla lägen. Bara vägen, stationen och du har lägets färg.
    init(_ mood: Mood) {
        (land, park, water, building, road, label, haloHex) =
            ("#14161B", "#18201D", "#10222B", "#1B1E24", "#343944", "#9AA0A8", "#14161B")
        routeHex = mood.accentHex
    }

    var route: Color { Color(uiColor: UIColor(hex: routeHex)) }
    var halo: Color { Color(uiColor: UIColor(hex: haloHex)) }

    /// Stilen som på webben: bara mark, park, vatten, hus, gator och gatunamn, plus din väg och stationen.
    var styleJSON: String {
        """
        {"version":8,
         "glyphs":"https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
         "sources":{
           "tiles":{"type":"vector","url":"https://tiles.openfreemap.org/planet"},
           "route":{"type":"geojson","data":{"type":"FeatureCollection","features":[]}},
           "station":{"type":"geojson","data":{"type":"FeatureCollection","features":[]}}},
         "layers":[
           {"id":"background","type":"background","paint":{"background-color":"\(land)"}},
           {"id":"park","type":"fill","source":"tiles","source-layer":"park","paint":{"fill-color":"\(park)"}},
           {"id":"water","type":"fill","source":"tiles","source-layer":"water","paint":{"fill-color":"\(water)"}},
           {"id":"building","type":"fill","source":"tiles","source-layer":"building","minzoom":14,"paint":{"fill-color":"\(building)"}},
           {"id":"road","type":"line","source":"tiles","source-layer":"transportation",
            "filter":["!in","class","rail","transit","ferry"],
            "layout":{"line-cap":"round","line-join":"round"},
            "paint":{"line-color":"\(road)","line-width":["interpolate",["exponential",1.5],["zoom"],12,0.6,17,6]}},
           {"id":"road-name","type":"symbol","source":"tiles","source-layer":"transportation_name","minzoom":14,
            "layout":{"symbol-placement":"line","text-field":["get","name"],"text-font":["Noto Sans Regular"],"text-size":13},
            "paint":{"text-color":"\(label)","text-halo-color":"\(haloHex)","text-halo-width":1.5}},
           {"id":"route","type":"line","source":"route","layout":{"line-cap":"round","line-join":"round"},
            "paint":{"line-color":"\(routeHex)","line-width":6}},
           {"id":"station","type":"circle","source":"station",
            "paint":{"circle-radius":9,"circle-color":"\(routeHex)","circle-stroke-color":"\(haloHex)","circle-stroke-width":3}},
           {"id":"station-name","type":"symbol","source":"station",
            "layout":{"text-field":["get","name"],"text-font":["Noto Sans Bold"],"text-size":15,"text-offset":[0,1.3],"text-anchor":"top"},
            "paint":{"text-color":"\(routeHex)","text-halo-color":"\(haloHex)","text-halo-width":2}}]}
        """
    }

    /// Byter färg på en karta som redan är laddad, utan att ladda om den.
    func paint(_ style: MLNStyle) {
        func color(_ hex: String) -> NSExpression { NSExpression(forConstantValue: UIColor(hex: hex)) }
        (style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer)?.backgroundColor = color(land)
        (style.layer(withIdentifier: "park") as? MLNFillStyleLayer)?.fillColor = color(park)
        (style.layer(withIdentifier: "water") as? MLNFillStyleLayer)?.fillColor = color(water)
        (style.layer(withIdentifier: "building") as? MLNFillStyleLayer)?.fillColor = color(building)
        (style.layer(withIdentifier: "road") as? MLNLineStyleLayer)?.lineColor = color(road)
        if let names = style.layer(withIdentifier: "road-name") as? MLNSymbolStyleLayer {
            names.textColor = color(label)
            names.textHaloColor = color(haloHex)
        }
        (style.layer(withIdentifier: "route") as? MLNLineStyleLayer)?.lineColor = color(routeHex)
        if let station = style.layer(withIdentifier: "station") as? MLNCircleStyleLayer {
            station.circleColor = color(routeHex)
            station.circleStrokeColor = color(haloHex)
        }
        if let name = style.layer(withIdentifier: "station-name") as? MLNSymbolStyleLayer {
            name.textColor = color(routeHex)
            name.textHaloColor = color(haloHex)
        }
    }
}

/// MapLibre-kartan. Det enda man kan göra med fingrarna är att zooma runt sig själv.
private struct WalkMap: UIViewRepresentable {
    let theme: MapTheme
    let position: Coordinate?
    let heading: Double?
    let route: [CLLocationCoordinate2D]
    let station: Stop?

    static let zoom = 17.0
    static let pitch = 30.0
    static let minTurn = 2.0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("walk-style.json")
        try? theme.styleJSON.write(to: file, atomically: true, encoding: .utf8)
        let view = MLNMapView(frame: .zero, styleURL: file)
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.anchorRotateOrZoomGesturesToCenterCoordinate = true
        view.compassView.isHidden = true
        view.logoView.isHidden = true
        view.attributionButton.tintColor = UIColor(hex: theme.label)
        // Över kortet längst ner, så att kartans upphovsrätt syns.
        view.attributionButtonMargins = CGPoint(x: 12, y: 130)
        view.setCenter(CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686), zoomLevel: 14, animated: false)
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(view)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: WalkMap?
        private var style: MLNStyle?
        private var painted: MapTheme?
        private var drawnRoute: [CLLocationCoordinate2D] = []
        private var drawnStation: Stop?
        private var placed = false

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            self.style = style
            painted = parent?.theme
            drawnRoute = []
            drawnStation = nil
            refresh(mapView)
        }

        func refresh(_ view: MLNMapView) {
            guard let parent else { return }
            follow(view, parent)
            guard let style else { return }
            if painted != parent.theme {
                view.attributionButton.tintColor = UIColor(hex: parent.theme.label)
                parent.theme.paint(style)
                painted = parent.theme
            }
            if !same(parent.route, drawnRoute), let source = style.source(withIdentifier: "route") as? MLNShapeSource {
                var points = parent.route
                source.shape = points.isEmpty ? nil : MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
                drawnRoute = parent.route
            }
            if parent.station != drawnStation, let source = style.source(withIdentifier: "station") as? MLNShapeSource {
                if let station = parent.station {
                    let point = MLNPointFeature()
                    point.coordinate = CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon)
                    point.attributes = ["name": station.name]
                    source.shape = point
                } else {
                    source.shape = nil
                }
                drawnStation = parent.station
            }
        }

        private func same(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
        }

        /// Det du har framför dig är uppåt på skärmen. Kompassen darrar hela tiden,
        /// så små vridningar och förflyttningar får vara.
        private func follow(_ view: MLNMapView, _ parent: WalkMap) {
            guard let position = parent.position else { return }
            let center = CLLocationCoordinate2D(latitude: position.lat, longitude: position.lon)
            let heading = parent.heading ?? view.direction
            if !placed {
                placed = true
                view.setCenter(center, zoomLevel: WalkMap.zoom, direction: heading, animated: false)
                let camera = view.camera
                camera.pitch = WalkMap.pitch
                view.setCamera(camera, animated: false)
                return
            }
            let turned = abs((heading - view.direction + 540).truncatingRemainder(dividingBy: 360) - 180)
            let moved = distanceMeters(Coordinate(lat: view.centerCoordinate.latitude, lon: view.centerCoordinate.longitude), position)
            if turned < WalkMap.minTurn && moved < 1 { return }
            let camera = view.camera
            camera.centerCoordinate = center
            camera.heading = heading
            camera.pitch = WalkMap.pitch
            view.setCamera(camera, withDuration: 0.25, animationTimingFunction: CAMediaTimingFunction(name: .linear))
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}
