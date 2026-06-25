import Testing
import AVFoundation
@testable import KeyboardSound

private final class SpyPlayer: SoundPlaying {
    var calls: [(buffer: AVAudioPCMBuffer, volume: Float)] = []
    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        calls.append((buffer, volume))
    }
}

private func makeController(enabled: Bool, volume: Double) -> (KeySoundController, SpyPlayer, Settings) {
    let suite = "ctrl-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = Settings(defaults: defaults)
    settings.enabled = enabled
    settings.volume = volume
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let bank = ClickSoundBank(format: format, tone: 0.6, sharpness: 0.7, preset: .clicky)
    let spy = SpyPlayer()
    return (KeySoundController(settings: settings, bank: bank, player: spy), spy, settings)
}

@Test func disabledDoesNotPlay() {
    let (controller, spy, _) = makeController(enabled: false, volume: 0.5)
    controller.handle(KeyEvent(keyCode: 0, phase: .down))
    #expect(spy.calls.isEmpty)
}

@Test func enabledPlaysWithVolume() {
    let (controller, spy, _) = makeController(enabled: true, volume: 0.42)
    controller.handle(KeyEvent(keyCode: 0, phase: .down))
    #expect(spy.calls.count == 1)
    #expect(abs(spy.calls[0].volume - 0.42) < 0.0001)
}

@Test func playsForBothPhases() {
    let (controller, spy, _) = makeController(enabled: true, volume: 0.5)
    controller.handle(KeyEvent(keyCode: 0, phase: .down))
    controller.handle(KeyEvent(keyCode: 0, phase: .up))
    #expect(spy.calls.count == 2)
}
