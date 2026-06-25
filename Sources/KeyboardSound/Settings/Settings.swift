import Foundation
import Combine

/// 사용자 설정. UserDefaults에 영속화하고 변경을 발행한다.
final class Settings: ObservableObject {
    private enum Keys {
        static let enabled = "enabled"
        static let presetID = "presetID"
        static let volume = "volume"
        static let tone = "tone"
        static let sharpness = "sharpness"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var presetID: String { didSet { defaults.set(presetID, forKey: Keys.presetID) } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }
    @Published var tone: Double { didSet { defaults.set(tone, forKey: Keys.tone) } }
    @Published var sharpness: Double { didSet { defaults.set(sharpness, forKey: Keys.sharpness) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.presetID: Preset.clicky.id,
            Keys.volume: 0.7,
            Keys.tone: Preset.clicky.tone,
            Keys.sharpness: Preset.clicky.sharpness,
        ])
        self.enabled = defaults.bool(forKey: Keys.enabled)
        self.presetID = defaults.string(forKey: Keys.presetID) ?? Preset.clicky.id
        self.volume = defaults.double(forKey: Keys.volume)
        self.tone = defaults.double(forKey: Keys.tone)
        self.sharpness = defaults.double(forKey: Keys.sharpness)
    }

    /// 프리셋 선택: presetID + tone + sharpness를 프리셋 값으로 세팅.
    func applyPreset(_ preset: Preset) {
        presetID = preset.id
        tone = preset.tone
        sharpness = preset.sharpness
    }

    /// 슬라이더 직접 조정 → custom으로 전환.
    func userAdjustedTone(_ value: Double) {
        tone = value
        presetID = "custom"
    }

    func userAdjustedSharpness(_ value: Double) {
        sharpness = value
        presetID = "custom"
    }

    /// 현재 프리셋의 내부값(decay/body/humanization) 소스. custom이면 clicky 폴백.
    var currentPreset: Preset {
        Preset.with(id: presetID) ?? .clicky
    }
}
