import Foundation
import Testing
@testable import NastaTagCore

/// 1794812400 är en måndag 08:20 i Stockholm, 1794931200 en tisdag 17:20.
private let mondayMorning = Date(timeIntervalSince1970: 1_794_812_400)
private let tuesdayEvening = Date(timeIntervalSince1970: 1_794_931_200)
private let tuesdayLate = tuesdayEvening.addingTimeInterval(6 * 3600)

@Test func theEndsTellTheStory() {
    #expect(stockholmHour(mondayMorning) == 8)
    let morning = TripStage.allCases.map { stageEnds($0, label: "Jobbet", trainTime: mondayMorning, mode: 1) }
    #expect(morning[0].start == "bed.double.fill" && morning[0].end == "figure.walk")
    #expect(morning[1].start == "figure.walk" && morning[1].end == stopSymbol)
    #expect(morning[2].start == stopSymbol && morning[2].end == Mode(1).symbol)
    #expect(morning[3].start == Mode(1).symbol && morning[3].end == "briefcase.fill")
    // Varje skede börjar där det förra slutade.
    for i in 1..<morning.count { #expect(morning[i].start == morning[i - 1].end) }
}

@Test func homeIsTheSofaOrTheBed() {
    #expect(originSymbol(label: "Hem", trainTime: tuesdayEvening) == "briefcase.fill")
    #expect(destinationSymbol(label: "Hem", trainTime: tuesdayEvening) == "sofa.fill")
    #expect(destinationSymbol(label: "Hem", trainTime: tuesdayLate) == "bed.double.fill")
    #expect(originSymbol(label: "Jobbet", trainTime: tuesdayEvening) == "house.fill", "till jobbet på eftermiddagen")
    #expect(originSymbol(label: "Gymmet", trainTime: mondayMorning) == "house.fill")
    #expect(destinationSymbol(label: "Gymmet", trainTime: mondayMorning) == "mappin")
}

@Test func theBarFillsOverTheRightTime() {
    let leaveBy = mondayMorning, train = mondayMorning.addingTimeInterval(8 * 60), arrival = train.addingTimeInterval(23 * 60)
    #expect(stageInterval(.home, leaveBy: leaveBy, trainTime: train, arrival: arrival) == leaveBy.addingTimeInterval(-15 * 60)...leaveBy)
    #expect(stageInterval(.walking, leaveBy: leaveBy, trainTime: train, arrival: arrival) == nil, "på väg fylls det efter sträckan")
    #expect(stageInterval(.atStop, leaveBy: leaveBy, trainTime: train, arrival: arrival) == train.addingTimeInterval(-15 * 60)...train)
    #expect(stageInterval(.onboard, leaveBy: leaveBy, trainTime: train, arrival: arrival) == train...arrival)
    #expect(stageInterval(.onboard, leaveBy: leaveBy, trainTime: train, arrival: nil) == train...train.addingTimeInterval(60))
}

@Test func walkingFillsByDistance() {
    #expect(walkedFraction(startMeters: 400, leftMeters: 400) == 0)
    #expect(walkedFraction(startMeters: 400, leftMeters: 100) == 0.75)
    #expect(walkedFraction(startMeters: 400, leftMeters: 500) == 0, "åt fel håll")
    #expect(walkedFraction(startMeters: 0, leftMeters: 0) == 1)
    #expect(metersText(347) == "350 m")
    #expect(metersText(4) == "10 m")
    #expect(metersText(1260) == "1,3 km")
}

#if canImport(ActivityKit) && os(iOS)
@Test func oldLockScreensStillDecode() throws {
    let state = TripAttributes.ContentState(status: .calm, leaveBy: mondayMorning, trainTime: mondayMorning, line: "43",
                                            towards: "Södertälje", station: "Karlberg", key: "k", mode: 1, minutes: 3)
    #expect(state.currentStage == .home)
    var boarded = state
    boarded.boarded = true
    #expect(boarded.currentStage == .onboard)
}
#endif
