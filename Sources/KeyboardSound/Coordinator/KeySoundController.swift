import Foundation

/// 키 이벤트를 받아 enabled면 뱅크에서 버퍼를 골라 재생기로 보낸다.
final class KeySoundController {
    private let settings: Settings
    private let bank: ClickSoundBank
    private let player: SoundPlaying

    init(settings: Settings, bank: ClickSoundBank, player: SoundPlaying) {
        self.settings = settings
        self.bank = bank
        self.player = player
    }

    func handle(_ event: KeyEvent) {
        guard settings.enabled else { return }
        let buffer = bank.buffer(forKeyCode: event.keyCode, phase: event.phase)
        player.play(buffer, volume: Float(settings.volume))
    }
}
