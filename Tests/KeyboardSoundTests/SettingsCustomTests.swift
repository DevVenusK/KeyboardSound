import Testing
import Foundation
@testable import KeyboardSound

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sc-\(UUID().uuidString)")!
}

@Test func selectCustomSetsCustomID() {
    let s = Settings(defaults: freshDefaults())
    s.selectCustom()
    #expect(s.selectedSwitchID == Preset.customID)
}

@Test func selectCustomPersistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.selectCustom()
    let s2 = Settings(defaults: d)
    #expect(s2.selectedSwitchID == "custom")
}

@Test func selectingSynthAfterCustomStillWorks() {
    let s = Settings(defaults: freshDefaults())
    s.selectCustom()
    s.selectSwitch(.red)                       // 합성 복귀
    #expect(s.selectedSwitchID == "red")
    #expect(abs(s.tone - Preset.red.tone) < 0.0001)
}
