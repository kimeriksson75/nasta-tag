import SwiftUI

/// Ring A: mörk botten överallt, och läget syns i en enda färg på ringen, rubriken och knappen.
/// Grönt gott om tid, gult skorna på, rött spring, grått när inget tåg finns.
public enum Mood: Sendable {
    case idle, calm, hurry, rush

    public init(_ status: Status?) {
        switch status {
        case .calm: self = .calm
        case .hurry: self = .hurry
        case .rush: self = .rush
        case .missed, nil: self = .idle
        }
    }

    /// Lägets färg som hex, för kartan.
    public var accentHex: String {
        switch self {
        case .idle: "#6B7079"
        case .calm: "#3DDC97"
        case .hurry: "#FFC24B"
        case .rush: "#FF5A5F"
        }
    }

    public var accent: Color { Color(hex: accentHex) }
    public var background: Color { Color(hex: "#0E0F12") }
    public var ink: Color { Color(hex: "#EDEEF0") }
    public var muted: Color { Color(hex: "#9AA0A8") }
    /// Ringens spår och tunna kanter.
    public var track: Color { Color(hex: "#23262D") }
    public var line: Color { Color(hex: "#3A3E46") }
    /// Kort som ligger på botten, som raden till kartan.
    public var card: Color { Color(hex: "#16181D") }
}

public extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}
