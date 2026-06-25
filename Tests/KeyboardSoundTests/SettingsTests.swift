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
    #expect(s.presetID == "clicky")
    #expect(s.volume > 0 && s.volume <= 1)
}

@Test func persistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.volume = 0.33
    s1.presetID = "thock"
    let s2 = Settings(defaults: d)
    #expect(abs(s2.volume - 0.33) < 0.0001)
    #expect(s2.presetID == "thock")
}

@Test func applyPresetSetsToneAndSharpness() {
    let s = Settings(defaults: freshDefaults())
    s.applyPreset(.thock)
    #expect(s.presetID == "thock")
    #expect(abs(s.tone - Preset.thock.tone) < 0.0001)
    #expect(abs(s.sharpness - Preset.thock.sharpness) < 0.0001)
}

@Test func userAdjustingSliderSwitchesToCustom() {
    let s = Settings(defaults: freshDefaults())
    s.applyPreset(.clicky)
    s.userAdjustedTone(0.1)
    #expect(s.presetID == "custom")
    #expect(abs(s.tone - 0.1) < 0.0001)
}

@Test func currentPresetFallsBackToClicky() {
    let s = Settings(defaults: freshDefaults())
    s.presetID = "custom"
    #expect(s.currentPreset == .clicky)   // custom일 때 내부값은 clicky 폴백
}
