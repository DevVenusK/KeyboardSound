import Testing
@testable import KeyboardSound

@Test func fourSwitchPresets() {
    #expect(Preset.all.count == 4)
    #expect(Preset.with(id: "blue") == .blue)
    #expect(Preset.with(id: "topre") == .topre)
    #expect(Preset.with(id: "nope") == nil)
}

@Test func blueBrighterThanTopre() {
    #expect(Preset.blue.tone > Preset.topre.tone)
    #expect(Preset.blue.sharpness > Preset.topre.sharpness)
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

@Test func onlyBlueClicks() {
    #expect(Preset.blue.clickAmount > 0)
    #expect(Preset.brown.clickAmount == 0)
    #expect(Preset.red.clickAmount == 0)
    #expect(Preset.topre.clickAmount == 0)
}
