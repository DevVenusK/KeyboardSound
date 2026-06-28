import Foundation
import Combine

/// 사용자 설정. UserDefaults에 영속화하고 변경을 발행한다.
/// 톤/샤프함/무게/울림은 선택된 스위치별로 따로 기억한다.
final class Settings: ObservableObject {
    /// 무게/울림 슬라이더의 중립 기본값(0.5 = ×1.0). 톤/샤프함 기본값은 스위치 프리셋에서 온다.
    static let neutralWeight = 0.5
    static let neutralRing = 0.5

    private enum Keys {
        static let enabled = "enabled"
        static let selectedSwitchID = "selectedSwitchID"
        static let volume = "volume"
        static func tone(_ id: String) -> String { "switch.\(id).tone" }
        static func sharpness(_ id: String) -> String { "switch.\(id).sharpness" }
        static func weight(_ id: String) -> String { "switch.\(id).weight" }
        static func ring(_ id: String) -> String { "switch.\(id).ring" }
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }

    /// 현재 선택된 스위치. 변경 시 그 스위치의 톤/샤프/무게/울림을 로드한다.
    @Published var selectedSwitchID: String {
        didSet {
            defaults.set(selectedSwitchID, forKey: Keys.selectedSwitchID)
            loadAdjustments(for: selectedSwitchID)
        }
    }

    // 현재 스위치 스코프 값. 변경 시 현재 스위치 아래로 저장.
    @Published var tone: Double      { didSet { defaults.set(tone, forKey: Keys.tone(selectedSwitchID)) } }
    @Published var sharpness: Double { didSet { defaults.set(sharpness, forKey: Keys.sharpness(selectedSwitchID)) } }
    @Published var weight: Double    { didSet { defaults.set(weight, forKey: Keys.weight(selectedSwitchID)) } }
    @Published var ring: Double      { didSet { defaults.set(ring, forKey: Keys.ring(selectedSwitchID)) } }

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
        self.weight = defaults.object(forKey: Keys.weight(id)) as? Double ?? Self.neutralWeight
        self.ring = defaults.object(forKey: Keys.ring(id)) as? Double ?? Self.neutralRing
    }

    /// 스위치 선택: id 설정(→ didSet이 그 스위치 값 로드).
    func selectSwitch(_ preset: Preset) {
        selectedSwitchID = preset.id
    }

    /// 커스텀 샘플 프리셋 선택. (톤/샤프 등은 커스텀 모드에서 미사용.)
    func selectCustom() {
        selectedSwitchID = Preset.customID
    }

    /// 현재 스위치의 캐릭터(decay/body/humanization/clickAmount) 소스.
    var currentSwitch: Preset {
        Preset.with(id: selectedSwitchID) ?? .blue
    }

    /// 현재 스위치의 톤/샤프/무게/울림을 그 스위치 기본값으로 되돌린다.
    func resetCurrentSwitch() {
        let preset = currentSwitch
        tone = preset.tone
        sharpness = preset.sharpness
        weight = Self.neutralWeight
        ring = Self.neutralRing
    }

    /// 선택된 스위치의 저장값을 published 프로퍼티에 로드(없으면 기본값).
    private func loadAdjustments(for id: String) {
        let preset = Preset.with(id: id) ?? .blue
        tone = defaults.object(forKey: Keys.tone(id)) as? Double ?? preset.tone
        sharpness = defaults.object(forKey: Keys.sharpness(id)) as? Double ?? preset.sharpness
        weight = defaults.object(forKey: Keys.weight(id)) as? Double ?? Self.neutralWeight
        ring = defaults.object(forKey: Keys.ring(id)) as? Double ?? Self.neutralRing
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
