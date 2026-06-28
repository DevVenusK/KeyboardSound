import Testing
import AVFoundation
@testable import KeyboardSound

private final class SpySamplePlayer: SamplePlaying {
    var calls: [(buffer: AVAudioPCMBuffer, volume: Float)] = []
    func playSample(_ buffer: AVAudioPCMBuffer, volume: Float) { calls.append((buffer, volume)) }
}

private final class StubSampleProvider: SampleProviding {
    var buffer: AVAudioPCMBuffer?
    init(buffer: AVAudioPCMBuffer?) { self.buffer = buffer }
}

private final class CountingSynthPlayer: SoundPlaying {
    var calls = 0
    func play(_ buffer: AVAudioPCMBuffer, volume: Float) { calls += 1 }
}

private func makeBuffer() -> AVAudioPCMBuffer {
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 64)!
    b.frameLength = 64
    return b
}

private func makeCustomController(bufferPresent: Bool)
    -> (KeySoundController, SpySamplePlayer, CountingSynthPlayer, Settings) {
    let defaults = UserDefaults(suiteName: "cc-\(UUID().uuidString)")!
    let settings = Settings(defaults: defaults)
    settings.enabled = true
    settings.volume = 0.5
    settings.selectCustom()
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let bank = ClickSoundBank(format: fmt, tone: 0.6, sharpness: 0.7, preset: .blue)
    let synth = CountingSynthPlayer()
    let sample = SpySamplePlayer()
    let store = StubSampleProvider(buffer: bufferPresent ? makeBuffer() : nil)
    let c = KeySoundController(settings: settings, bank: bank, player: synth,
                              sampleStore: store, samplePlayer: sample)
    return (c, sample, synth, settings)
}

@Test func customPlaysSampleOnDownOnly() {
    let (c, sample, synth, _) = makeCustomController(bufferPresent: true)
    c.handle(KeyEvent(keyCode: 0, phase: .down))
    c.handle(KeyEvent(keyCode: 0, phase: .up))
    #expect(sample.calls.count == 1)                       // down만
    #expect(synth.calls == 0)                              // 합성 경로 미사용
    #expect(abs(sample.calls[0].volume - 0.5) < 0.0001)
}

@Test func customWithoutBufferIsSilent() {
    let (c, sample, _, _) = makeCustomController(bufferPresent: false)
    c.handle(KeyEvent(keyCode: 0, phase: .down))
    #expect(sample.calls.isEmpty)
}

@Test func customRespectsDisabled() {
    let (c, sample, _, settings) = makeCustomController(bufferPresent: true)
    settings.enabled = false
    c.handle(KeyEvent(keyCode: 0, phase: .down))
    #expect(sample.calls.isEmpty)
}
