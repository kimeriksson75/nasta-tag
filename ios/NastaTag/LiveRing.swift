import NastaTagCore
import SwiftUI

/// Ringen räknas om varje bildruta från när du ska gå, så den glider hela tiden i stället för att hoppa
/// var femte sekund. Färgen tar den från läget, samma läge som rubriken och knappen, så alla byter
/// samtidigt. När läget eller resan byts glider ringen och färgen över på samma halva sekund som resten.
struct LiveRing: View {
    /// När du ska gå, eller nil när det inte finns någon resa.
    let leaveAt: Date?
    /// Avgången ringen gäller, så att ett byte kan tonas över.
    let key: String?
    /// Läget som resten av skärmen visar.
    let mood: Mood
    var lineWidth: CGFloat

    @State private var memory = RingMemory()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let target = ringTarget(leaveAt: leaveAt, mood: mood, now: context.date)
            let drawn = memory.draw(target: RingState(fraction: target.fraction, color: RGB(hex: target.mood.accentHex)),
                                    identity: "\(key ?? "")|\(target.mood)", at: context.date)
            // En rund ände ritar en prick även när ringen är tom, så den tonas bort sista biten.
            let visible: Double = min(1, drawn.fraction * 100)
            ZStack {
                Circle().stroke(Color(hex: "#23262D"), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: drawn.fraction)
                    .stroke(drawn.color.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .opacity(visible)
                    .rotationEffect(.degrees(-90))
            }
            .padding(lineWidth / 2)
        }
        .accessibilityHidden(true)
    }
}

struct RingState {
    var fraction: Double
    var color: RGB
}

/// Det som ritades senast och en pågående övertoning. En klass, så att varje bildruta
/// kan minnas utan att rita om vyn en gång till. Ett byte märks på att resan eller läget
/// är ett annat än i förra bildrutan, så övertoningen börjar i samma bildruta som bytet.
final class RingMemory {
    private var last = RingState(fraction: 0, color: RGB(hex: Mood.idle.accentHex))
    private var lastIdentity: String?
    private var from: RingState?
    private var start = Date.distantPast
    /// Samma tid som rubriken och knappen tonar över på.
    static let duration = 0.5

    func draw(target: RingState, identity: String, at date: Date) -> RingState {
        if let lastIdentity, lastIdentity != identity {
            from = last
            start = date
        }
        lastIdentity = identity
        var state = target
        if let from {
            let p = min(1, max(0, date.timeIntervalSince(start) / Self.duration))
            let t = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 // mjuk in och ut
            state = RingState(fraction: from.fraction + (target.fraction - from.fraction) * t,
                              color: from.color.mix(target.color, t))
            if p >= 1 { self.from = nil }
        }
        last = state
        return state
    }
}

/// En färg som går att blanda.
struct RGB: Equatable {
    var r, g, b: Double

    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        r = Double((value >> 16) & 0xff) / 255
        g = Double((value >> 8) & 0xff) / 255
        b = Double(value & 0xff) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        var out = self
        out.r += (other.r - r) * t
        out.g += (other.g - g) * t
        out.b += (other.b - b) * t
        return out
    }
}

/// Den stora ringen på startsidan, med minuterna i mitten.
struct Ring: View {
    let trip: Trip?
    let wait: String
    let caption: String
    let mood: Mood

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                LiveRing(leaveAt: trip?.leaveAt, key: trip?.key, mood: mood, lineWidth: size * 14 / 260)
                VStack(spacing: 4) {
                    Text(wait)
                        .font(.system(size: size * 0.18, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                    Text(caption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mood.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                }
                // Texten har fast plats, så att ringen och raderna står still när orden byts.
                .frame(width: size * 0.62, height: size * 0.4)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}
