import Foundation
import Combine

/// 사용자 설정. UserDefaults에 영속화하고 변경을 발행한다.
/// 톤/샤프함은 선택된 스위치별로 따로 기억한다.
final class Settings: ObservableObject {
    private enum Keys {
        static let enabled = "enabled"
        static let selectedSwitchID = "selectedSwitchID"
        static let volume = "volume"
        static func tone(_ id: String) -> String { "switch.\(id).tone" }
        static func sharpness(_ id: String) -> String { "switch.\(id).sharpness" }
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }

    /// 현재 선택된 스위치. 변경 시 그 스위치의 톤/샤프를 로드한다.
    @Published var selectedSwitchID: String {
        didSet {
            defaults.set(selectedSwitchID, forKey: Keys.selectedSwitchID)
            loadAdjustments(for: selectedSwitchID)
        }
    }

    /// 현재 스위치의 톤. 변경 시 현재 스위치 아래로 저장.
    @Published var tone: Double {
        didSet { defaults.set(tone, forKey: Keys.tone(selectedSwitchID)) }
    }
    /// 현재 스위치의 샤프함. 변경 시 현재 스위치 아래로 저장.
    @Published var sharpness: Double {
        didSet { defaults.set(sharpness, forKey: Keys.sharpness(selectedSwitchID)) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateIfNeeded(defaults)

        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.selectedSwitchID: Preset.blue.id,
            Keys.volume: 0.7,
        ])

        let id = defaults.string(forKey: Keys.selectedSwitchID) ?? Preset.blue.id
        let preset = Preset.with(id: id) ?? .blue

        self.enabled = defaults.bool(forKey: Keys.enabled)
        self.volume = defaults.double(forKey: Keys.volume)
        self.selectedSwitchID = id   // init 중에는 didSet 미발동 → 아래에서 직접 로드
        self.tone = defaults.object(forKey: Keys.tone(id)) as? Double ?? preset.tone
        self.sharpness = defaults.object(forKey: Keys.sharpness(id)) as? Double ?? preset.sharpness
    }

    /// 스위치 선택: id 설정(→ didSet이 그 스위치 톤/샤프 로드).
    func selectSwitch(_ preset: Preset) {
        selectedSwitchID = preset.id
    }

    /// 현재 스위치의 캐릭터(decay/body/humanization/clickAmount) 소스.
    var currentSwitch: Preset {
        Preset.with(id: selectedSwitchID) ?? .blue
    }

    /// 선택된 스위치의 저장 톤/샤프를 published 프로퍼티에 로드(없으면 스위치 기본값).
    private func loadAdjustments(for id: String) {
        let preset = Preset.with(id: id) ?? .blue
        tone = defaults.object(forKey: Keys.tone(id)) as? Double ?? preset.tone
        sharpness = defaults.object(forKey: Keys.sharpness(id)) as? Double ?? preset.sharpness
    }

    /// 옛 모델(presetID + 단일 tone/sharpness) → 새 모델 1회성 마이그레이션.
    /// "presetID" 키 유무만으로 판별: 마이그레이션 실행 시 해당 키를 삭제하므로 자동 1회성.
    private static func migrateIfNeeded(_ defaults: UserDefaults) {
        guard let oldID = defaults.string(forKey: "presetID") else { return }
        let map = ["clicky": "blue", "tactile": "brown", "linear": "red", "thock": "topre"]
        let newID = map[oldID] ?? "blue"
        defaults.set(newID, forKey: Keys.selectedSwitchID)
        if let t = defaults.object(forKey: "tone") as? Double { defaults.set(t, forKey: Keys.tone(newID)) }
        if let s = defaults.object(forKey: "sharpness") as? Double { defaults.set(s, forKey: Keys.sharpness(newID)) }
        defaults.removeObject(forKey: "presetID")
        defaults.removeObject(forKey: "tone")
        defaults.removeObject(forKey: "sharpness")
    }
}
