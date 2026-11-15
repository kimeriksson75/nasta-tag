import Foundation
import NastaTagCore
import Testing

@Test func stagesFollowTheWalk() {
    #expect(walkStage(startMeters: 630, leftMeters: 630) == nil)
    #expect(walkStage(startMeters: 630, leftMeters: 600) == nil, "står still eller har bara tagit några steg")
    #expect(walkStage(startMeters: 630, leftMeters: 560) == .going)
    #expect(walkStage(startMeters: 630, leftMeters: 370) == .halfway)
    #expect(walkStage(startMeters: 630, leftMeters: 230) == .halfway)
    #expect(walkStage(startMeters: 630, leftMeters: 120) == .near)
    #expect(walkStage(startMeters: 630, leftMeters: nil) == .there)
    // Kort väg: nära direkt när du har kommit i gång.
    #expect(walkStage(startMeters: 180, leftMeters: 120) == .near)
}

@Test func cheersAreShortSentencesWithoutNumbers() {
    for list in Array(Voice.walkCheers.values) + Array(Voice.walkCheersRush.values) {
        for cheer in list {
            #expect(cheer.first?.isUppercase == true, "\(cheer)")
            #expect(cheer.hasSuffix(".") || cheer.hasSuffix("!"), "\(cheer)")
            let hasNumber = cheer.contains { $0.isNumber }
            #expect(!hasNumber, "\(cheer)")
            #expect(cheer.count <= 24, "ryms bredvid ringen på kartan: \(cheer)")
        }
    }
    for stage in WalkStage.allCases {
        #expect(Voice.walkCheers[stage]?.isEmpty == false && Voice.walkCheersRush[stage]?.isEmpty == false)
    }
}

@Test func cheersKeepTheUrgency() {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(walkHeadline(stage: nil, status: .calm, trainTime: time) == nil)
    #expect(walkHeadline(stage: .halfway, status: .missed, trainTime: time) == nil)
    for stage in WalkStage.allCases {
        let rush = walkHeadline(stage: stage, status: .rush, trainTime: time)!
        #expect(rush.hasSuffix("!"), "\(rush)")
        #expect(!Voice.words(rush).contains("gå"), "rött säger aldrig gå: \(rush)")
        let calm = walkHeadline(stage: stage, status: .calm, trainTime: time)!
        #expect(Voice.walkCheers[stage]!.contains(calm))
        #expect(walkHeadline(stage: stage, status: .calm, trainTime: time) == calm, "byts inte medan du tittar")
    }
}
