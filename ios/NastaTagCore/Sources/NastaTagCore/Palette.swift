import SwiftUI

/// Samma färger som webbappen: grönt gott om tid, gult raska på, rött spring, mörkt när inget tåg finns.
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

    public var background: Color {
        switch self {
        case .idle: Color(red: 0.078, green: 0.090, blue: 0.110)
        case .calm: Color(red: 0.082, green: 0.478, blue: 0.294)
        case .hurry: Color(red: 0.949, green: 0.714, blue: 0.196)
        case .rush: Color(red: 0.851, green: 0.176, blue: 0.176)
        }
    }

    public var ink: Color {
        self == .hurry ? Color(red: 0.078, green: 0.090, blue: 0.110) : .white
    }

    public var muted: Color {
        switch self {
        case .idle: Color(white: 0.70)
        case .calm: Color(red: 0.89, green: 0.96, blue: 0.93)
        case .hurry: Color(red: 0.24, green: 0.20, blue: 0.08)
        case .rush: Color(red: 1.0, green: 0.90, blue: 0.90)
        }
    }
}

/// Kort besked för låsskärmen, där det bara får plats några ord.
public func activityLead(_ status: Status) -> String {
    switch status {
    case .calm: "Gå om"
    case .hurry: "Raska på, gå om"
    case .rush: "Spring, gå"
    case .missed: "Tåget har gått"
    }
}
