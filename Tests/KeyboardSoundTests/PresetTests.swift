import Testing
@testable import KeyboardSound

@Test func fourBuiltInPresets() {
    #expect(Preset.all.count == 4)
    #expect(Preset.with(id: "clicky") == .clicky)
    #expect(Preset.with(id: "thock") == .thock)
    #expect(Preset.with(id: "nope") == nil)
}

@Test func clickyBrighterThanThock() {
    #expect(Preset.clicky.tone > Preset.thock.tone)
    #expect(Preset.clicky.sharpness > Preset.thock.sharpness)
}

@Test func higherToneSliderGivesHigherFrequency() {
    let low = SoundParameterMapping.toneFrequency(tone: 0.2, group: .normal)
    let high = SoundParameterMapping.toneFrequency(tone: 0.9, group: .normal)
    #expect(high > low)
}

@Test func wideGroupIsLowerThanNormal() {
    let normal = SoundParameterMapping.toneFrequency(tone: 0.5, group: .normal)
    let wide = SoundParameterMapping.toneFrequency(tone: 0.5, group: .wide)
    #expect(wide < normal)
}
