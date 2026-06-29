import AVFoundation

/// 키 이벤트를 받아 enabled면 적절한 경로로 소리를 재생한다.
/// - 합성 프리셋: 뱅크에서 버퍼를 골라 폴리포니 재생기(player)로.
/// - 커스텀 프리셋: down에서만, 샘플 버퍼가 있으면 모노폰 재생기(samplePlayer)로.
final class KeySoundController {
    private let settings: Settings
    private let bank: ClickSoundBank
    private let player: SoundPlaying
    private let sampleStore: SampleProviding?
    private let samplePlayer: SamplePlaying?

    init(settings: Settings, bank: ClickSoundBank, player: SoundPlaying,
         sampleStore: SampleProviding? = nil, samplePlayer: SamplePlaying? = nil) {
        self.settings = settings
        self.bank = bank
        self.player = player
        self.sampleStore = sampleStore
        self.samplePlayer = samplePlayer
    }

    func handle(_ event: KeyEvent) {
        guard settings.enabled else { return }

        if settings.selectedSwitchID == Preset.customID {
            guard event.phase == .down, let buffer = sampleStore?.buffer else { return }
            samplePlayer?.playSample(buffer, volume: Float(settings.volume))
            return
        }

        let buffer = bank.buffer(forKeyCode: event.keyCode, phase: event.phase)
        player.play(buffer, volume: Float(settings.volume))
    }
}
