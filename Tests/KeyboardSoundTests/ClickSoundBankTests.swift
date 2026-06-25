import Testing
import AVFoundation
@testable import KeyboardSound

private func makeBank() -> ClickSoundBank {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    return ClickSoundBank(format: format, tone: 0.6, sharpness: 0.7, preset: .clicky, variantCount: 6)
}

@Test func bufferIsNonEmpty() {
    let bank = makeBank()
    let buf = bank.buffer(forKeyCode: 0, phase: .down)
    #expect(buf.frameLength > 0)
}

@Test func wideKeyUsesLongerBufferThanNormal() {
    let bank = makeBank()
    let normal = bank.buffer(forKeyCode: 0, phase: .down)     // 'a'
    let wide = bank.buffer(forKeyCode: 49, phase: .down)      // space (thock, 긴 decay)
    #expect(wide.frameLength > normal.frameLength)
}

@Test func variantCyclesOnRepeatedPress() {
    let bank = makeBank()
    // 같은 키를 6번 누르면 변형 인덱스가 순환 → 적어도 두 종류 이상의 버퍼 객체
    var seen = Set<ObjectIdentifier>()
    for _ in 0..<6 {
        let b = bank.buffer(forKeyCode: 0, phase: .down)
        seen.insert(ObjectIdentifier(b))
    }
    #expect(seen.count >= 2)
}

@Test func upBufferShorterThanDown() {
    let bank = makeBank()
    let down = bank.buffer(forKeyCode: 0, phase: .down)
    let up = bank.buffer(forKeyCode: 0, phase: .up)
    #expect(up.frameLength < down.frameLength)
}

@Test func regenerateKeepsBufferUsable() {
    let bank = makeBank()
    bank.regenerate(tone: 0.2, sharpness: 0.3, preset: .thock)
    let buf = bank.buffer(forKeyCode: 0, phase: .down)
    #expect(buf.frameLength > 0)
}
