import Testing
import Foundation
@testable import KeyboardSound

private func freshDefaults() -> UserDefaults {
    let suite = "test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

@Test func defaultsAreSane() {
    let s = Settings(defaults: freshDefaults())
    #expect(s.enabled == true)
    #expect(s.selectedSwitchID == "blue")
    #expect(s.volume > 0 && s.volume <= 1)
}

@Test func selectSwitchLoadsItsDefaults() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.topre)
    #expect(s.selectedSwitchID == "topre")
    #expect(abs(s.tone - Preset.topre.tone) < 0.0001)
    #expect(abs(s.sharpness - Preset.topre.sharpness) < 0.0001)
}

@Test func toneRememberedPerSwitch() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.blue)
    s.tone = 0.9
    s.selectSwitch(.red)                          // red 기본값 로드
    #expect(abs(s.tone - Preset.red.tone) < 0.0001)
    s.selectSwitch(.blue)                         // blue 조정값 복원
    #expect(abs(s.tone - 0.9) < 0.0001)
}

@Test func persistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.volume = 0.33
    s1.selectSwitch(.topre)
    s1.tone = 0.4
    let s2 = Settings(defaults: d)
    #expect(abs(s2.volume - 0.33) < 0.0001)
    #expect(s2.selectedSwitchID == "topre")
    #expect(abs(s2.tone - 0.4) < 0.0001)
}

@Test func currentSwitchSuppliesCharacter() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.topre)
    #expect(s.currentSwitch == .topre)
}

@Test func migratesOldPresetID() {
    let d = freshDefaults()
    d.set("thock", forKey: "presetID")
    d.set(0.27, forKey: "tone")
    let s = Settings(defaults: d)
    #expect(s.selectedSwitchID == "topre")
    #expect(abs(s.tone - 0.27) < 0.0001)
}

@Test func weightAndRingRememberedPerSwitch() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.blue)
    s.weight = 0.8
    s.ring = 0.2
    s.selectSwitch(.red)                                   // red 기본값(중립)
    #expect(abs(s.weight - Settings.neutralWeight) < 0.0001)
    #expect(abs(s.ring - Settings.neutralRing) < 0.0001)
    s.selectSwitch(.blue)                                  // blue 조정값 복원
    #expect(abs(s.weight - 0.8) < 0.0001)
    #expect(abs(s.ring - 0.2) < 0.0001)
}

@Test func resetRestoresSwitchDefaults() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.topre)
    s.tone = 0.1; s.sharpness = 0.9; s.weight = 0.2; s.ring = 0.8
    s.resetCurrentSwitch()
    #expect(abs(s.tone - Preset.topre.tone) < 0.0001)
    #expect(abs(s.sharpness - Preset.topre.sharpness) < 0.0001)
    #expect(abs(s.weight - Settings.neutralWeight) < 0.0001)
    #expect(abs(s.ring - Settings.neutralRing) < 0.0001)
}
