import NastaTagCore
import SwiftUI

/// Ringen räknas om varje bildruta från när du ska gå, så den glider hela tiden i stället för att hoppa
/// var femte sekund. Färgen tonar över till nästa läge under minuten innan det byts, och när resan
/// byts (Snooze, ny avgång) glider ringen och färgen över till den nya i stället för att hoppa.
struct LiveRing: View {
    /// När du ska gå, eller nil när det inte finns någon resa.
    let leaveAt: Date?
    /// Avgången ringen gäller, så att ett byte kan tonas över.
    let key: String?
    var lineWidth: CGFloat

    @State private var memory = RingMemory()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let drawn = memory.draw(target: target(at: context.date), at: context.date)
            ZStack {
                Circle().stroke(Color(hex: "#23262D"), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: drawn.fraction)
                    .stroke(drawn.color.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(lineWidth / 2)
        }
        .onChange(of: key) { memory.beginTransition() }
        .accessibilityHidden(true)
    }

    private func target(at date: Date) -> RingState {
        guard let leaveAt else { return RingState(fraction: 0, color: .missed) }
        let slack = leaveAt.timeIntervalSince(date) / 60
        if slack < 0 { return RingState(fraction: 0, color: .missed) }
        return RingState(fraction: min(1, max(0.04, slack / 15)), color: RGB.forSlack(slack))
    }
}

struct RingState {
    var fraction: Double
    var color: RGB
}

/// Det som ritades senast och en pågående övertoning. En klass, så att varje bildruta
/// kan minnas utan att rita om vyn en gång till.
final class RingMemory {
    private var last = RingState(fraction: 0, color: .missed)
    private var from: RingState?
    private var start = Date.distantPast
    private var hasDrawn = false
    static let duration = 0.6

    func beginTransition() {
        guard hasDrawn else { return }
        from = last
        start = Date()
    }

    func draw(target: RingState, at date: Date) -> RingState {
        var state = target
        if let from {
            let p = min(1, max(0, date.timeIntervalSince(start) / Self.duration))
            let t = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 // mjuk in och ut
            state = RingState(fraction: from.fraction + (target.fraction - from.fraction) * t,
                              color: from.color.mix(target.color, t))
            if p >= 1 { self.from = nil }
        }
        last = state
        hasDrawn = true
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

    static let calm = RGB(hex: Mood.calm.accentHex)
    static let hurry = RGB(hex: Mood.hurry.accentHex)
    static let rush = RGB(hex: Mood.rush.accentHex)
    static let missed = RGB(hex: Mood.idle.accentHex)

    var color: Color { Color(red: r, green: g, blue: b) }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        var out = self
        out.r += (other.r - r) * t
        out.g += (other.g - g) * t
        out.b += (other.b - b) * t
        return out
    }

    /// Lägets färg, och under minuten före ett byte en blandning på väg mot nästa.
    static func forSlack(_ slack: Double) -> RGB {
        let fade = 1.0
        if slack >= hurryLimitMinutes + fade { return calm }
        if slack >= hurryLimitMinutes { return hurry.mix(calm, (slack - hurryLimitMinutes) / fade) }
        if slack >= rushLimitMinutes + fade { return hurry }
        if slack >= rushLimitMinutes { return rush.mix(hurry, (slack - rushLimitMinutes) / fade) }
        return rush
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
                LiveRing(leaveAt: trip?.leaveAt, key: trip?.key, lineWidth: size * 14 / 260)
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
