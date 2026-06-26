# 기계식 스위치 타건음 재현 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 프리셋(clicky/tactile/linear/thock)을 실제 스위치 타건음(청축/갈축/적축/토프레)으로 교체하고, 스위치별로 톤·샤프함을 기억하는 미세 조정을 제공한다.

**Architecture:** 완전 절차적 합성 유지. `ClickSynth`에 청축 "딸깍"을 위한 클릭 트랜지언트 레이어를 추가(`clickAmount` 파라미터 1개 신설). `Preset`을 4개 스위치로 재정의하고, `Settings`를 스위치별 톤/샤프 기억 모델로 재작성(custom 개념 제거 + 옛 데이터 마이그레이션).

**Tech Stack:** Swift 6 tools / 언어모드 v5, macOS 13+, AVFoundation, Combine, SwiftUI, Swift Testing.

## Global Constraints

- 배포 타깃: macOS 13 이상 (`Package.swift` `platforms: [.macOS(.v13)]`).
- 합성은 **완전 절차적** — 녹음/오디오 자산 파일을 추가하지 않는다.
- `ClickSynth.render`는 **순수 함수** 유지: 동일 파라미터·시드 → 동일 출력. 출력은 `[-1, 1]`로 클램프.
- 스위치 표시 이름은 **한글**: 청축/갈축/적축/토프레. id는 영문 안정값: `blue`/`brown`/`red`/`topre`.
- 테스트는 **Swift Testing**(`@Test`/`#expect`), 기존 파일 스타일을 따른다.
- 작업마다 테스트 그린 상태에서 **자주 커밋**.

---

### Task 1: 클릭 트랜지언트 레이어 (`clickAmount`)

**Files:**
- Modify: `Sources/KeyboardSound/Sound/SoundParameters.swift`
- Modify: `Sources/KeyboardSound/Sound/ClickSynth.swift`
- Test: `Tests/KeyboardSoundTests/ClickSynthTests.swift`

**Interfaces:**
- Produces: `SoundParameters.clickAmount: Double` (기본값 0). `ClickSynth.render`가 `clickAmount>0`일 때 고주파 클릭 버스트를 본체에 더한다.
- Consumes: 없음(기존 `BiquadBandpass`, `SplitMix64` 재사용).

- [ ] **Step 1: 실패 테스트 작성** — `Tests/KeyboardSoundTests/ClickSynthTests.swift` 끝에 추가

```swift
@Test func clickAmountChangesOutput() {
    let synth = ClickSynth(sampleRate: 44100)
    let base = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                               bodyMix: 0.4, humanization: 0.2, clickAmount: 0.0)
    let clicky = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                                 bodyMix: 0.4, humanization: 0.2, clickAmount: 0.9)
    let a = synth.render(parameters: base, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let b = synth.render(parameters: clicky, phase: .down, pitchMultiplier: 1.0, seed: 7)
    #expect(a != b)
}

@Test func clickAddsEarlyEnergy() {
    let synth = ClickSynth(sampleRate: 44100)
    let base = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                               bodyMix: 0.4, humanization: 0.2, clickAmount: 0.0)
    let clicky = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                                 bodyMix: 0.4, humanization: 0.2, clickAmount: 0.9)
    let a = synth.render(parameters: base, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let b = synth.render(parameters: clicky, phase: .down, pitchMultiplier: 1.0, seed: 7)
    let window = min(220, a.count)   // 첫 ~5ms
    func energy(_ s: ArraySlice<Float>) -> Double { s.reduce(0) { $0 + Double($1 * $1) } }
    #expect(energy(b[0..<window]) > energy(a[0..<window]))
}

@Test func outputBoundedWithMaxClick() {
    let synth = ClickSynth(sampleRate: 44100)
    let p = SoundParameters(toneFrequency: 2000, sharpness: 0.7, decayTime: 0.05,
                            bodyMix: 0.4, humanization: 0.2, clickAmount: 1.0)
    let s = synth.render(parameters: p, phase: .down, pitchMultiplier: 1.0, seed: 3)
    for v in s { #expect(v.isFinite && v >= -1.0 && v <= 1.0) }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter clickAmountChangesOutput`
Expected: 컴파일 실패 — `SoundParameters`에 `clickAmount` 인자 없음.

- [ ] **Step 3: `SoundParameters`에 `clickAmount` 추가** — `Sources/KeyboardSound/Sound/SoundParameters.swift`

기존 struct에 마지막 필드로 추가(기본값 0이라 기존 호출부는 그대로 컴파일된다):

```swift
import Foundation

/// 합성기에 전달되는 실제 DSP 파라미터.
struct SoundParameters: Equatable {
    var toneFrequency: Double   // Hz, 클릭 중심 주파수
    var sharpness: Double       // 0...1 (어택 가파름 + 노이즈량)
    var decayTime: Double       // 초
    var bodyMix: Double         // 0...1 (바디:노이즈 비율)
    var humanization: Double    // 0...1 (변형 피치 지터 폭)
    var clickAmount: Double = 0 // 0...1 (청축 딸깍 트랜지언트 세기)
}
```

- [ ] **Step 4: `ClickSynth`에 클릭 레이어 추가** — `Sources/KeyboardSound/Sound/ClickSynth.swift`의 `render(...)`를 아래로 교체

```swift
    func render(parameters: SoundParameters, phase: KeyPhase, pitchMultiplier: Double, seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let isUp = (phase == .up)

        // 릴리스(up) 클릭은 더 짧고 약하게.
        let decay = parameters.decayTime * (isUp ? 0.6 : 1.0)
        let amplitude: Float = isUp ? 0.5 : 1.0

        let count = max(1, Int(decay * sampleRate))
        var out = [Float](repeating: 0, count: count)

        let toneHz = parameters.toneFrequency * pitchMultiplier
        let bodyHz = toneHz * 0.5
        let q = 1.0 + parameters.sharpness * 6.0
        var bandpass = BiquadBandpass(sampleRate: sampleRate, centerHz: toneHz, q: q)

        let noiseMix = Float(1.0 - parameters.bodyMix)
        let bodyMix = Float(parameters.bodyMix)
        let attackSamples = max(1, Int(0.001 * sampleRate))   // 1ms 어택
        let decayConst = max(0.0001, decay / 5.0)             // 5 시정수
        let twoPiBodyOverSr = 2.0 * Double.pi * bodyHz / sampleRate

        // 클릭 트랜지언트 레이어 (청축 click jacket): 본체와 독립된 RNG/필터/빠른 감쇠.
        // 별도 RNG를 써서 clickAmount 변화가 본체 노이즈 시퀀스에 영향을 주지 않게 한다.
        let clickAmt = Float(parameters.clickAmount)
        var clickRng = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        let clickHz = min(sampleRate * 0.45, 5000.0)          // 나이퀴스트 보호
        var clickBandpass = BiquadBandpass(sampleRate: sampleRate, centerHz: clickHz, q: 4.0)
        let clickDecayConst = max(0.0001, 0.004 / 5.0)        // ~4ms 매우 빠른 감쇠

        for n in 0..<count {
            // 엔벨로프: 선형 어택 후 지수 감쇠
            let env: Float
            if n < attackSamples {
                env = Float(n) / Float(attackSamples)
            } else {
                let tAfterAttack = Double(n - attackSamples) / sampleRate
                env = Float(exp(-tAfterAttack / decayConst))
            }

            let white = Float(rng.nextUnit() * 2.0 - 1.0)
            let noise = bandpass.process(white)
            let body = Float(sin(twoPiBodyOverSr * Double(n)))

            // 클릭 기여 (clickAmt==0이면 0, 기존 출력과 동일)
            var clickSample: Float = 0
            if clickAmt > 0 {
                let cWhite = Float(clickRng.nextUnit() * 2.0 - 1.0)
                let cFiltered = clickBandpass.process(cWhite)
                let cEnv = Float(exp(-Double(n) / sampleRate / clickDecayConst))
                clickSample = cFiltered * cEnv * clickAmt
            }

            var s = (noise * noiseMix + body * bodyMix) * env * amplitude + clickSample * amplitude
            s = max(-1.0, min(1.0, s))   // 소프트 클램프
            out[n] = s
        }
        return out
    }
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter ClickSynth`
Expected: 신규 3개 + 기존 5개 모두 PASS (기존 테스트는 `clickAmount` 기본 0이라 동작 불변).

- [ ] **Step 6: 커밋**

```bash
git add Sources/KeyboardSound/Sound/SoundParameters.swift Sources/KeyboardSound/Sound/ClickSynth.swift Tests/KeyboardSoundTests/ClickSynthTests.swift
git commit -m "feat: ClickSynth 클릭 트랜지언트 레이어(clickAmount) 추가"
```

---

### Task 2: `Preset.clickAmount` 필드 + 뱅크 전파

**Files:**
- Modify: `Sources/KeyboardSound/Sound/Preset.swift`
- Modify: `Sources/KeyboardSound/Sound/ClickSoundBank.swift:31-37`
- Test: `Tests/KeyboardSoundTests/PresetTests.swift`
- Test: `Tests/KeyboardSoundTests/ClickSoundBankTests.swift`

**Interfaces:**
- Produces: `Preset.clickAmount: Double`. `ClickSoundBank.regenerate`가 `preset.clickAmount`를 `SoundParameters.clickAmount`로 전달.
- Consumes: Task 1의 `SoundParameters.clickAmount`.
- 주의: 이 작업에서는 기존 프리셋 id(clicky/tactile/linear/thock)를 **유지**한다. id 교체는 Task 3.

- [ ] **Step 1: 실패 테스트 작성** — `Tests/KeyboardSoundTests/ClickSoundBankTests.swift` 끝에 추가

```swift
@Test func clickAmountPropagatesToBuffers() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let noClick = Preset(id: "x", name: "x", tone: 0.6, sharpness: 0.7,
                         decayTime: 0.05, bodyMix: 0.4, humanization: 0.0, clickAmount: 0.0)
    let withClick = Preset(id: "y", name: "y", tone: 0.6, sharpness: 0.7,
                           decayTime: 0.05, bodyMix: 0.4, humanization: 0.0, clickAmount: 0.9)
    let a = ClickSoundBank(format: format, tone: 0.6, sharpness: 0.7, preset: noClick, variantCount: 1)
    let b = ClickSoundBank(format: format, tone: 0.6, sharpness: 0.7, preset: withClick, variantCount: 1)
    let bufA = a.buffer(forKeyCode: 0, phase: .down)
    let bufB = b.buffer(forKeyCode: 0, phase: .down)
    // 첫 샘플 구간이 클릭 유무로 달라져야 한다.
    let n = min(Int(bufA.frameLength), Int(bufB.frameLength), 220)
    var differs = false
    for i in 0..<n where bufA.floatChannelData![0][i] != bufB.floatChannelData![0][i] { differs = true; break }
    #expect(differs)
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter clickAmountPropagatesToBuffers`
Expected: 컴파일 실패 — `Preset`에 `clickAmount` 인자 없음.

- [ ] **Step 3: `Preset`에 `clickAmount` 필드 추가** — `Sources/KeyboardSound/Sound/Preset.swift`

struct에 필드를 추가하고, 기존 4개 정적 프리셋에 `clickAmount` 값을 부여(clicky만 0.8). **id/이름은 이 작업에서 변경하지 않는다.**

```swift
struct Preset: Equatable, Identifiable {
    let id: String
    let name: String
    let tone: Double
    let sharpness: Double
    let decayTime: Double
    let bodyMix: Double
    let humanization: Double
    let clickAmount: Double

    static let clicky  = Preset(id: "clicky",  name: "Clicky",  tone: 0.78, sharpness: 0.85, decayTime: 0.045, bodyMix: 0.25, humanization: 0.15, clickAmount: 0.80)
    static let tactile = Preset(id: "tactile", name: "Tactile", tone: 0.55, sharpness: 0.60, decayTime: 0.060, bodyMix: 0.45, humanization: 0.20, clickAmount: 0.00)
    static let linear  = Preset(id: "linear",  name: "Linear",  tone: 0.50, sharpness: 0.35, decayTime: 0.050, bodyMix: 0.55, humanization: 0.15, clickAmount: 0.00)
    static let thock   = Preset(id: "thock",   name: "Thock",   tone: 0.25, sharpness: 0.30, decayTime: 0.090, bodyMix: 0.70, humanization: 0.25, clickAmount: 0.00)

    static let all: [Preset] = [.clicky, .tactile, .linear, .thock]

    static func with(id: String) -> Preset? {
        all.first { $0.id == id }
    }
}
```

(`SoundParameterMapping`은 동일 파일 하단에 그대로 둔다.)

- [ ] **Step 4: 뱅크가 `clickAmount` 전파하도록 수정** — `Sources/KeyboardSound/Sound/ClickSoundBank.swift`의 `SoundParameters(...)` 생성부

```swift
            let params = SoundParameters(
                toneFrequency: toneFreq,
                sharpness: sharpness,
                decayTime: preset.decayTime * decayMultiplier,
                bodyMix: preset.bodyMix,
                humanization: preset.humanization,
                clickAmount: preset.clickAmount
            )
```

- [ ] **Step 5: Preset 테스트 추가** — `Tests/KeyboardSoundTests/PresetTests.swift` 끝에 추가

```swift
@Test func clickyHasClickOthersDont() {
    #expect(Preset.clicky.clickAmount > 0)
    #expect(Preset.tactile.clickAmount == 0)
    #expect(Preset.linear.clickAmount == 0)
    #expect(Preset.thock.clickAmount == 0)
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter ClickSoundBank` 그리고 `swift test --filter Preset`
Expected: 신규 포함 모두 PASS.

- [ ] **Step 7: 커밋**

```bash
git add Sources/KeyboardSound/Sound/Preset.swift Sources/KeyboardSound/Sound/ClickSoundBank.swift Tests/KeyboardSoundTests/PresetTests.swift Tests/KeyboardSoundTests/ClickSoundBankTests.swift
git commit -m "feat: Preset.clickAmount + ClickSoundBank 전파"
```

---

### Task 3: 스위치 모델 전환 (프리셋 재정의 + 스위치별 톤/샤프 기억)

기존 프리셋 id를 4개 스위치로 교체하고, `Settings`를 스위치별 기억 모델로 재작성하며, 명칭을 스위치 용어로 통일한다. id 교체가 `Settings`/UI/AppDelegate/테스트로 파급되므로 한 작업에서 함께 그린 상태로 만든다.

**Files:**
- Modify: `Sources/KeyboardSound/Sound/Preset.swift`
- Modify: `Sources/KeyboardSound/Settings/Settings.swift` (전면 재작성)
- Modify: `Sources/KeyboardSound/App/AppDelegate.swift` (3곳)
- Modify: `Sources/KeyboardSound/UI/SettingsView.swift`
- Modify: `Sources/KeyboardSound/UI/StatusMenuController.swift` (2곳)
- Test: `Tests/KeyboardSoundTests/PresetTests.swift`
- Test: `Tests/KeyboardSoundTests/SettingsTests.swift`
- Test: `Tests/KeyboardSoundTests/ClickSoundBankTests.swift`

**Interfaces:**
- Produces: `Settings.selectedSwitchID: String`, `Settings.tone`/`sharpness`(현재 스위치 스코프, 스위치별 영속), `Settings.selectSwitch(_:)`, `Settings.currentSwitch: Preset`. `Preset.blue/.brown/.red/.topre`, `Preset.all == [.blue,.brown,.red,.topre]`.
- Consumes: Task 2의 `Preset.clickAmount`, `ClickSoundBank.regenerate(tone:sharpness:preset:)`.

- [ ] **Step 1: 새 Settings 동작 실패 테스트 작성** — `Tests/KeyboardSoundTests/SettingsTests.swift` **전체 교체**

```swift
import Testing
import Foundation
@testable import KeyboardSound

private func freshDefaults() -> UserDefaults {
    let suite = "test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

@Test func defaultsAreSane() {
    let s = Settings(defaults: freshDefaults())
    #expect(s.enabled == true)
    #expect(s.selectedSwitchID == "blue")
    #expect(s.volume > 0 && s.volume <= 1)
}

@Test func selectSwitchLoadsItsDefaults() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.topre)
    #expect(s.selectedSwitchID == "topre")
    #expect(abs(s.tone - Preset.topre.tone) < 0.0001)
    #expect(abs(s.sharpness - Preset.topre.sharpness) < 0.0001)
}

@Test func toneRememberedPerSwitch() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.blue)
    s.tone = 0.9
    s.selectSwitch(.red)                          // red 기본값 로드
    #expect(abs(s.tone - Preset.red.tone) < 0.0001)
    s.selectSwitch(.blue)                         // blue 조정값 복원
    #expect(abs(s.tone - 0.9) < 0.0001)
}

@Test func persistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.volume = 0.33
    s1.selectSwitch(.topre)
    s1.tone = 0.4
    let s2 = Settings(defaults: d)
    #expect(abs(s2.volume - 0.33) < 0.0001)
    #expect(s2.selectedSwitchID == "topre")
    #expect(abs(s2.tone - 0.4) < 0.0001)
}

@Test func currentSwitchSuppliesCharacter() {
    let s = Settings(defaults: freshDefaults())
    s.selectSwitch(.topre)
    #expect(s.currentSwitch == .topre)
}

@Test func migratesOldPresetID() {
    let d = freshDefaults()
    d.set("thock", forKey: "presetID")
    d.set(0.27, forKey: "tone")
    let s = Settings(defaults: d)
    #expect(s.selectedSwitchID == "topre")
    #expect(abs(s.tone - 0.27) < 0.0001)
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter Settings`
Expected: 컴파일 실패 — `selectedSwitchID`/`selectSwitch`/`Preset.topre` 미정의.

- [ ] **Step 3: `Preset`을 4개 스위치로 재정의** — `Sources/KeyboardSound/Sound/Preset.swift`의 정적 프리셋 블록 교체

```swift
    static let blue  = Preset(id: "blue",  name: "청축",  tone: 0.80, sharpness: 0.85, decayTime: 0.045, bodyMix: 0.25, humanization: 0.15, clickAmount: 0.80)
    static let brown = Preset(id: "brown", name: "갈축",  tone: 0.55, sharpness: 0.55, decayTime: 0.060, bodyMix: 0.45, humanization: 0.20, clickAmount: 0.00)
    static let red   = Preset(id: "red",   name: "적축",  tone: 0.45, sharpness: 0.35, decayTime: 0.050, bodyMix: 0.50, humanization: 0.15, clickAmount: 0.00)
    static let topre = Preset(id: "topre", name: "토프레", tone: 0.22, sharpness: 0.30, decayTime: 0.095, bodyMix: 0.72, humanization: 0.25, clickAmount: 0.00)

    static let all: [Preset] = [.blue, .brown, .red, .topre]
```

(`clicky/tactile/linear/thock` 정적 멤버는 삭제.)

- [ ] **Step 4: `Settings` 전면 재작성** — `Sources/KeyboardSound/Settings/Settings.swift` 전체 교체

```swift
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
    private static func migrateIfNeeded(_ defaults: UserDefaults) {
        guard defaults.object(forKey: Keys.selectedSwitchID) == nil,
              let oldID = defaults.string(forKey: "presetID") else { return }
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
```

- [ ] **Step 5: Settings 테스트 통과 확인** (UI/AppDelegate는 아직 옛 이름 참조라 전체 빌드는 실패할 수 있음 — 다음 스텝까지 진행)

Run: `swift test --filter Settings 2>&1 | tail -20`
Expected: 아직 다른 파일 컴파일 에러로 실패할 수 있음. Step 6~8 후 재확인.

- [ ] **Step 6: AppDelegate 와이어링 갱신** — `Sources/KeyboardSound/App/AppDelegate.swift`

(6a) 뱅크 초기화 `preset:` 인자:

```swift
        bank = ClickSoundBank(format: player.format,
                              tone: settings.tone,
                              sharpness: settings.sharpness,
                              preset: settings.currentSwitch)
```

(6b) Combine 키:

```swift
        settings.$tone
            .combineLatest(settings.$sharpness, settings.$selectedSwitchID)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.regenerateBank() }
            .store(in: &cancellables)
```

(6c) `regenerateBank()`:

```swift
    private func regenerateBank() {
        bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, preset: settings.currentSwitch)
    }
```

- [ ] **Step 7: SettingsView 갱신** — `Sources/KeyboardSound/UI/SettingsView.swift`의 `body` 교체 (custom 태그 제거, 피커는 selectedSwitchID, 슬라이더는 톤/샤프 직접 바인딩)

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyboardSound")
                .font(.headline)

            Picker("스위치", selection: Binding(
                get: { settings.selectedSwitchID },
                set: { id in
                    if let preset = Preset.with(id: id) { settings.selectSwitch(preset) }
                }
            )) {
                ForEach(Preset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.segmented)

            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            slider("톤",   value: Binding(get: { settings.tone }, set: { settings.tone = $0 }))
            slider("샤프함", value: Binding(get: { settings.sharpness }, set: { settings.sharpness = $0 }))

            Button("테스트 소리", action: onTest)
        }
        .padding(20)
        .frame(width: 320)
    }
```

- [ ] **Step 8: StatusMenuController 갱신** — `Sources/KeyboardSound/UI/StatusMenuController.swift`

(8a) 프리셋 서브메뉴의 선택 상태 비교:

```swift
            item.state = (settings.selectedSwitchID == preset.id) ? .on : .off
```

(8b) `selectPreset(_:)` 액션:

```swift
    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let preset = Preset.with(id: id) {
            settings.selectSwitch(preset)
        }
        rebuild()
    }
```

- [ ] **Step 9: PresetTests / ClickSoundBankTests의 옛 id 참조 갱신**

`Tests/KeyboardSoundTests/PresetTests.swift`의 처음 두 테스트와 `clickyHasClickOthersDont`를 교체:

```swift
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

@Test func onlyBlueClicks() {
    #expect(Preset.blue.clickAmount > 0)
    #expect(Preset.brown.clickAmount == 0)
    #expect(Preset.red.clickAmount == 0)
    #expect(Preset.topre.clickAmount == 0)
}
```

(`higherToneSliderGivesHigherFrequency`, `wideGroupIsLowerThanNormal`는 그대로 둔다.)

`Tests/KeyboardSoundTests/ClickSoundBankTests.swift`의 `makeBank()`와 `regenerateKeepsBufferUsable`에서 옛 id 교체:

```swift
private func makeBank() -> ClickSoundBank {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    return ClickSoundBank(format: format, tone: 0.6, sharpness: 0.7, preset: .blue, variantCount: 6)
}
```

```swift
@Test func regenerateKeepsBufferUsable() {
    let bank = makeBank()
    bank.regenerate(tone: 0.2, sharpness: 0.3, preset: .topre)
    let buf = bank.buffer(forKeyCode: 0, phase: .down)
    #expect(buf.frameLength > 0)
}
```

- [ ] **Step 10: 전체 빌드 + 테스트 통과 확인**

Run: `swift build && swift test 2>&1 | tail -15`
Expected: 빌드 성공, 전 테스트 PASS.

- [ ] **Step 11: 커밋**

```bash
git add Sources/KeyboardSound Tests/KeyboardSoundTests
git commit -m "feat: 청축/갈축/적축/토프레 스위치 + 스위치별 톤/샤프 기억"
```

---

### Task 4: .app 재빌드 + 귀 검증 및 파라미터 튜닝

스펙 §4 파라미터는 초기 추정값이다. 실제 .app으로 실행해 네 스위치를 들어보고, 필요 시 `Preset.swift`의 값을 조정한다.

**Files:**
- Modify (필요 시): `Sources/KeyboardSound/Sound/Preset.swift`

- [ ] **Step 1: .app 재빌드/재서명**

```bash
bash scripts/build-app.sh
```
Expected: "Build complete" + Developer ID 서명 메시지.

- [ ] **Step 2: 기존 인스턴스 종료 후 재실행**

```bash
pkill -f "KeyboardSound.app/Contents/MacOS/KeyboardSound" 2>/dev/null; sleep 1
open KeyboardSound.app
```

- [ ] **Step 3: 귀로 검증**

설정 창(메뉴바 → 사운드 설정…)에서 청축/갈축/적축/토프레를 차례로 선택하며 키를 눌러본다. 확인 항목:
- 청축에 또렷한 "딸깍(click)"이 있는가
- 토프레가 가장 낮고 묵직한 "통"인가
- 적축이 가장 깔끔/조용한가
- 각 스위치에서 톤/샤프 슬라이더가 그 스위치 기준으로 변하고, 스위치 전환 후 돌아오면 조정값이 유지되는가

- [ ] **Step 4 (필요 시): 파라미터 튜닝 후 재빌드**

`Sources/KeyboardSound/Sound/Preset.swift`의 해당 스위치 값을 귀에 맞게 조정하고 Step 1~3 반복. 만족스러우면:

```bash
git add Sources/KeyboardSound/Sound/Preset.swift
git commit -m "tune: 스위치 파라미터 청감 보정"
```

(조정이 없으면 이 커밋은 생략.)

---

## Self-Review

**Spec coverage:**
- §3 합성 모델(clickAmount + 클릭 레이어) → Task 1 ✓
- §4 네 스위치 프리셋 → Task 2(필드)+Task 3(id 재정의) ✓
- §5 스위치별 기억 데이터 모델 → Task 3 (Settings 재작성) ✓
- §6 AppDelegate/뱅크 재생성 → Task 3 Step 6 ✓
- §7 UI(설정/메뉴) → Task 3 Step 7~8 ✓
- §8 마이그레이션 → Task 3 Step 4 `migrateIfNeeded` + Step 1 테스트 ✓
- §9 테스트(ClickSynth/Bank/Settings/Preset) → Task 1·2·3 테스트 ✓

**Placeholder scan:** 모든 코드 스텝에 완전한 코드 포함, TBD/TODO 없음.

**Type consistency:** `Settings.selectedSwitchID/tone/sharpness/selectSwitch(_:)/currentSwitch`, `Preset.blue/.brown/.red/.topre + clickAmount`, `SoundParameters.clickAmount`, `ClickSoundBank.regenerate(tone:sharpness:preset:)` — 모든 작업에서 시그니처 일치.
