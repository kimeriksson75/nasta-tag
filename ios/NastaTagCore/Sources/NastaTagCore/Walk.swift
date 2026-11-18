import Foundation

// MARK: På väg till hållplatsen

/// Hur långt du har kommit på väg till hållplatsen. Rubriken på kartan hejar efter det.
public enum WalkStage: String, CaseIterable, Sendable {
    /// Du har börjat gå.
    case going
    /// Ungefär halvvägs.
    case halfway
    /// Nästan framme.
    case near
    /// Vid hållplatsen.
    case there
}

/// Så här långt behöver du ha gått innan appen säger något, så att den inte hejar på någon som står still.
public let walkStartedMeters = 50.0
/// Under så här mycket kvar är du nästan framme.
public let walkNearMeters = 150.0

/// Var på vägen du är. `startMeters` är sträckan när du började, `leftMeters` det som är kvar,
/// eller nil när du redan står vid hållplatsen. Nil betyder att du inte har kommit i gång än.
public func walkStage(startMeters: Double, leftMeters: Double?) -> WalkStage? {
    guard let left = leftMeters else { return .there }
    let walked = startMeters - left
    guard walked >= walkStartedMeters else { return nil }
    if left < walkNearMeters { return .near }
    if walked >= startMeters * 0.4 { return .halfway }
    return .going
}

extension Voice {
    /// Uppmuntran medan du går. Inga siffror: avståndet står redan under.
    public static let walkCheers: [WalkStage: [String]] = [
        .going: ["Bra start.", "Då kör vi.", "Fint tempo."],
        .halfway: ["Halvvägs där.", "Du fixar detta.", "Kämpa på."],
        .near: ["Så nära nu.", "Inte långt kvar nu.", "Snart framme."],
        // Kortet under säger redan "Du är framme", så rubriken säger det inte en gång till.
        .there: ["Snyggt jobbat.", "Bra gått."],
    ]
    /// När det är bråttom hejar rubriken men säger fortfarande att det brådskar.
    public static let walkCheersRush: [WalkStage: [String]] = [
        .going: ["Bra, håll farten!"],
        .halfway: ["Halvvägs, öka lite!"],
        .near: ["Nästan där, kör!"],
        .there: ["Du hann!"],
    ]
}

/// Rubriken på kartan medan du går, eller nil när den vanliga rubriken gäller:
/// innan du har kommit i gång, och när avgången redan är missad.
public func walkHeadline(stage: WalkStage?, status: Status, trainTime: Date) -> String? {
    guard let stage, status != .missed else { return nil }
    let list = (status == .rush ? Voice.walkCheersRush : Voice.walkCheers)[stage] ?? []
    guard !list.isEmpty else { return nil }
    return Voice.pick(list, seed: trainTime, salt: 10 + UInt64(WalkStage.allCases.firstIndex(of: stage)!))
}
