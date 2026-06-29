import Testing
@testable import KeyboardSound

@Test func customIDIsStable() {
    #expect(Preset.customID == "custom")
}

@Test func customIDIsNotASynthPreset() {
    #expect(Preset.with(id: Preset.customID) == nil)
    #expect(Preset.all.count == 4)
}
