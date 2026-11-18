import Foundation

// Resan i fyra skeden, som förloppet på låsskärmen följer. Varje skede svarar på frågan som gäller
// just då, och ändarna på förloppet säger var i resan du är: från sängen till att gå, från att gå
// till hållplatsen, från hållplatsen till tåget och från tåget till skrivbordet eller soffan.

public enum TripStage: String, Codable, CaseIterable, Sendable {
    /// Du har inte gått än. Förloppet fylls fram till gå senast.
    case home
    /// Du är på väg. Förloppet fylls efter hur långt du har gått.
    case walking
    /// Du står vid hållplatsen. Förloppet fylls fram till avgången.
    case atStop
    /// Du sitter på tåget. Förloppet fylls fram till att du är framme.
    case onboard
}

/// Så lång tid före gå senast, eller före avgången vid hållplatsen, som förloppet börjar fyllas.
/// Samma kvart som ringen i appen.
public let stageBarMinutes = ringFullMinutes

/// Symbolen för hållplatsen, i änden av förloppet på väg dit.
public let stopSymbol = "mappin.and.ellipse"

/// Var du är innan du går. Till jobbet på morgonen ligger du i sängen, hem är du på jobbet.
public func originSymbol(label: String?, trainTime: Date) -> String {
    switch label {
    case "Jobbet": stockholmHour(trainTime) < 11 ? "bed.double.fill" : "house.fill"
    case "Hem": "briefcase.fill"
    default: "house.fill"
    }
}

/// Dit du ska. Hem på kvällen väntar soffan, sent på kvällen sängen.
public func destinationSymbol(label: String?, trainTime: Date) -> String {
    let hour = stockholmHour(trainTime)
    switch label {
    case "Jobbet": return "briefcase.fill"
    case "Hem": return hour >= 21 || hour < 4 ? "bed.double.fill" : "sofa.fill"
    default: return "mappin"
    }
}

/// Symbolerna i förloppets två ändar.
public func stageEnds(_ stage: TripStage, label: String?, trainTime: Date, mode: Int) -> (start: String, end: String) {
    let vehicle = Mode(mode).symbol
    switch stage {
    case .home: return (originSymbol(label: label, trainTime: trainTime), "figure.walk")
    case .walking: return ("figure.walk", stopSymbol)
    case .atStop: return (stopSymbol, vehicle)
    case .onboard: return (vehicle, destinationSymbol(label: label, trainTime: trainTime))
    }
}

/// Tiden förloppet fylls över, så att iOS kan flytta det själv. Nil på väg, där det fylls efter sträckan.
public func stageInterval(_ stage: TripStage, leaveBy: Date, trainTime: Date, arrival: Date?) -> ClosedRange<Date>? {
    switch stage {
    case .home: return leaveBy.addingTimeInterval(-stageBarMinutes * 60)...leaveBy
    case .walking: return nil
    case .atStop: return trainTime.addingTimeInterval(-stageBarMinutes * 60)...trainTime
    case .onboard:
        let end = max(arrival ?? trainTime, trainTime.addingTimeInterval(60))
        return trainTime...end
    }
}

/// Hur stor del av vägen till hållplatsen du har gått, från 0 till 1.
public func walkedFraction(startMeters: Double, leftMeters: Double) -> Double {
    guard startMeters > 0 else { return 1 }
    return min(1, max(0, 1 - leftMeters / startMeters))
}

/// Sträckan kvar, avrundad så att den inte fladdrar: tiotal meter under en kilometer, sedan en decimal.
public func metersText(_ meters: Double) -> String {
    if meters < 1000 { return "\(max(10, Int((meters / 10).rounded()) * 10)) m" }
    let km = (meters / 100).rounded() / 10
    return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
}
