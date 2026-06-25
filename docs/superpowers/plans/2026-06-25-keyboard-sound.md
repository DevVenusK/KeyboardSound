# KeyboardSound Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 메뉴바 앱이 물리 키 입력마다 합성된 기계식 키보드 클릭음을 전역 재생하고, 사용자가 프리셋/슬라이더로 소리를 조절한다.

**Architecture:** `CGEventTap`(듣기 전용)으로 전역 키 이벤트를 받아 자동반복을 거른 뒤, keyCode→그룹별 사전 렌더된 합성 PCM 버퍼를 `AVAudioEngine` 플레이어 노드 풀로 재생한다. 설정은 `UserDefaults`로 영속화하고 메뉴바 + SwiftUI 설정 창으로 조절한다. 순수 로직(필터/DSP/뱅크/설정/컨트롤러)은 단위 테스트, 시스템 의존부(탭/오디오/UI)는 구현+수동 검증.

**Tech Stack:** Swift, Swift Package Manager(executable), Swift Testing, AppKit, AVFoundation, SwiftUI, Combine, CoreGraphics, ApplicationServices (모두 시스템 프레임워크, 외부 의존 0).

## Global Constraints

- 최소 macOS 버전: **13.0** (`platforms: [.macOS(.v13)]`, Info.plist `LSMinimumSystemVersion = 13.0`)
- 사운드는 **합성만** — 녹음/샘플 오디오 에셋 금지 (저작권 안전·배포 가능)
- 외부 패키지 의존 **0** — 시스템 프레임워크만 사용
- 빌드: SPM → `.app` 번들 조립 + **ad-hoc 서명**; bundle id `com.keyboardsound.app` 는 재빌드 간 **고정**
- 메뉴바 전용: `LSUIElement = true` + 런타임 `NSApp.setActivationPolicy(.accessory)`
- 자동반복(키 꾹 누름) 입력은 **무시**; 이벤트 탭은 **listen-only**(이벤트 수정 금지)
- 테스트 프레임워크: **Swift Testing** (`import Testing`); Swift 도구 6.0 + 언어 모드 v5
- 키 감지에는 **손쉬운 사용(Accessibility) 권한** 필수

---

## File Structure

```
Package.swift
Sources/KeyboardSound/
  main.swift                         앱 진입점 (NSApplication 구동)
  App/AppDelegate.swift              전 컴포넌트 와이어링 + 생명주기 + 권한 워처
  KeyEvents/KeyEvent.swift           KeyEvent 모델 (keyCode, phase)
  KeyEvents/KeyGroup.swift           KeyGroup enum + keyCode→group 매핑
  KeyEvents/KeyEventFilter.swift     순수 판정: 자동반복 필터 + 모디파이어 전이
  KeyEvents/KeyEventMonitor.swift    CGEventTap 래퍼 (시스템 의존)
  Sound/Random.swift                 SplitMix64 결정적 RNG
  Sound/Biquad.swift                 BiquadBandpass 필터
  Sound/Preset.swift                 Preset 정의 + 내장 4종 + 파라미터 매핑
  Sound/SoundParameters.swift        합성 파라미터 구조체
  Sound/ClickSynth.swift             순수 DSP: 파라미터→[Float] 샘플 렌더
  Sound/ClickSoundBank.swift         뱅크: 그룹/변형 사전 렌더 + 버퍼 선택
  Sound/SoundPlayer.swift            SoundPlaying 프로토콜 + AVAudioEngine 구현
  Settings/Settings.swift            ObservableObject + UserDefaults
  Coordinator/KeySoundController.swift  키 이벤트→버퍼→재생 조율
  Permissions/AccessibilityPermission.swift  AX 권한 헬퍼
  UI/StatusMenuController.swift      NSStatusItem + 메뉴
  UI/SettingsView.swift              SwiftUI 설정 창 뷰
  UI/SettingsWindowController.swift  NSWindow + NSHostingController 호스팅
Tests/KeyboardSoundTests/
  KeyGroupTests.swift
  KeyEventFilterTests.swift
  RandomTests.swift
  PresetTests.swift
  ClickSynthTests.swift
  ClickSoundBankTests.swift
  SettingsTests.swift
  KeySoundControllerTests.swift
scripts/build-app.sh
README.md
```

---

## Task 1: 패키지 스캐폴드

**Files:**
- Create: `Package.swift`
- Create: `Sources/KeyboardSound/main.swift` (임시 스텁)
- Create: `Tests/KeyboardSoundTests/KeyGroupTests.swift` (임시 빈 테스트)

**Interfaces:**
- Consumes: (없음)
- Produces: 빌드 가능한 SPM 패키지. 이후 모든 태스크가 이 타깃에 파일 추가.

- [ ] **Step 1: `Package.swift` 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardSound",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyboardSound",
            path: "Sources/KeyboardSound"
        ),
        .testTarget(
            name: "KeyboardSoundTests",
            dependencies: ["KeyboardSound"],
            path: "Tests/KeyboardSoundTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 임시 진입점 스텁 작성**

`Sources/KeyboardSound/main.swift`:

```swift
import Foundation

// 임시 스텁 — Task 14에서 NSApplication 구동으로 교체
print("KeyboardSound build OK")
```

- [ ] **Step 3: 임시 테스트 작성**

`Tests/KeyboardSoundTests/KeyGroupTests.swift`:

```swift
import Testing
@testable import KeyboardSound

@Test func packageBuilds() {
    #expect(true)
}
```

- [ ] **Step 4: 빌드 + 테스트 실행**

Run: `swift build && swift test`
Expected: 빌드 성공, 테스트 1개 PASS.

- [ ] **Step 5: 커밋**

```bash
git add Package.swift Sources Tests
git commit -m "feat: SPM 패키지 스캐폴드 + 임시 진입점/테스트"
```

---

## Task 2: KeyEvent 모델 + KeyGroup 매핑

**Files:**
- Create: `Sources/KeyboardSound/KeyEvents/KeyEvent.swift`
- Create: `Sources/KeyboardSound/KeyEvents/KeyGroup.swift`
- Modify: `Tests/KeyboardSoundTests/KeyGroupTests.swift` (스텁 교체)

**Interfaces:**
- Consumes: (없음)
- Produces:
  - `enum KeyPhase { case down, up }`
  - `struct KeyEvent: Equatable { let keyCode: Int; let phase: KeyPhase }`
  - `enum KeyGroup { case normal, wide }`
  - `enum KeyGroupMap { static func group(for keyCode: Int) -> KeyGroup }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/KeyGroupTests.swift` (전체 교체):

```swift
import Testing
@testable import KeyboardSound

@Test func spaceIsWide() {
    #expect(KeyGroupMap.group(for: 49) == .wide)   // space
}

@Test func returnAndDeleteAndTabAreWide() {
    #expect(KeyGroupMap.group(for: 36) == .wide)    // return
    #expect(KeyGroupMap.group(for: 51) == .wide)    // delete (backspace)
    #expect(KeyGroupMap.group(for: 48) == .wide)    // tab
}

@Test func arrowsAreWide() {
    for code in [123, 124, 125, 126] {              // left, right, down, up
        #expect(KeyGroupMap.group(for: code) == .wide)
    }
}

@Test func modifiersAreWide() {
    for code in [54, 55, 56, 60, 58, 61, 59, 62, 57, 63] {
        #expect(KeyGroupMap.group(for: code) == .wide)
    }
}

@Test func letterIsNormal() {
    #expect(KeyGroupMap.group(for: 0) == .normal)   // 'a'
    #expect(KeyGroupMap.group(for: 1) == .normal)   // 's'
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter KeyGroupTests`
Expected: FAIL — `KeyGroupMap`, `KeyEvent`, `KeyPhase`, `KeyGroup` 미정의 컴파일 에러.

- [ ] **Step 3: 모델 구현**

`Sources/KeyboardSound/KeyEvents/KeyEvent.swift`:

```swift
import Foundation

/// 키 이벤트의 단계. 누름과 뗌을 구분한다.
enum KeyPhase {
    case down
    case up
}

/// 필터링을 거친 정규화된 키 이벤트.
struct KeyEvent: Equatable {
    let keyCode: Int
    let phase: KeyPhase
}
```

`Sources/KeyboardSound/KeyEvents/KeyGroup.swift`:

```swift
import Foundation

/// 사운드 그룹. normal = 일반 클릭, wide = 낮고 묵직한 thock.
enum KeyGroup {
    case normal
    case wide
}

/// macOS 가상 키코드 → 사운드 그룹 매핑.
enum KeyGroupMap {
    /// thock(wide) 그룹으로 처리할 키코드 집합.
    static let wideKeyCodes: Set<Int> = [
        49,                 // space
        36, 76,             // return, keypad enter
        51, 117,            // delete(backspace), forward delete
        48,                 // tab
        53,                 // escape
        123, 124, 125, 126, // arrows: left, right, down, up
        54, 55,             // command (right, left)
        56, 60,             // shift (left, right)
        58, 61,             // option (left, right)
        59, 62,             // control (left, right)
        57,                 // caps lock
        63,                 // fn
    ]

    static func group(for keyCode: Int) -> KeyGroup {
        wideKeyCodes.contains(keyCode) ? .wide : .normal
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter KeyGroupTests`
Expected: PASS (5개 테스트).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/KeyEvents Tests/KeyboardSoundTests/KeyGroupTests.swift
git commit -m "feat: KeyEvent 모델 + keyCode→그룹 매핑"
```

---

## Task 3: KeyEventFilter (자동반복/모디파이어 전이 판정)

**Files:**
- Create: `Sources/KeyboardSound/KeyEvents/KeyEventFilter.swift`
- Create: `Tests/KeyboardSoundTests/KeyEventFilterTests.swift`

**Interfaces:**
- Consumes: `KeyEvent`, `KeyPhase` (Task 2)
- Produces:
  - `enum RawKeyEventType { case keyDown, keyUp, flagsChanged }`
  - `enum KeyEventFilter { static func decide(type:keyCode:isAutorepeat:previousFlags:currentFlags:modifierMask:) -> KeyEvent?; static func modifierMask(forKeyCode:) -> UInt64? }`
  - 모디파이어 마스크 상수는 `CGEventFlags`의 rawValue를 그대로 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/KeyEventFilterTests.swift`:

```swift
import Testing
@testable import KeyboardSound

@Test func keyDownEmitsDown() {
    let e = KeyEventFilter.decide(type: .keyDown, keyCode: 0, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == KeyEvent(keyCode: 0, phase: .down))
}

@Test func autorepeatIsIgnored() {
    let e = KeyEventFilter.decide(type: .keyDown, keyCode: 0, isAutorepeat: true,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == nil)
}

@Test func keyUpEmitsUp() {
    let e = KeyEventFilter.decide(type: .keyUp, keyCode: 0, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: 0, modifierMask: 0)
    #expect(e == KeyEvent(keyCode: 0, phase: .up))
}

@Test func modifierPressEmitsDown() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: 0, currentFlags: mask, modifierMask: mask)
    #expect(e == KeyEvent(keyCode: 56, phase: .down))
}

@Test func modifierReleaseEmitsUp() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: mask, currentFlags: 0, modifierMask: mask)
    #expect(e == KeyEvent(keyCode: 56, phase: .up))
}

@Test func modifierUnchangedEmitsNil() {
    let mask: UInt64 = 0b1000
    let e = KeyEventFilter.decide(type: .flagsChanged, keyCode: 56, isAutorepeat: false,
                                  previousFlags: mask, currentFlags: mask, modifierMask: mask)
    #expect(e == nil)
}

@Test func modifierMaskMappingKnownKeys() {
    #expect(KeyEventFilter.modifierMask(forKeyCode: 56) != nil)   // shift
    #expect(KeyEventFilter.modifierMask(forKeyCode: 0) == nil)    // 'a' 아님
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter KeyEventFilterTests`
Expected: FAIL — `KeyEventFilter`, `RawKeyEventType` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/KeyEvents/KeyEventFilter.swift`:

```swift
import CoreGraphics

/// CGEventType를 테스트 가능한 형태로 추상화한 타입.
enum RawKeyEventType {
    case keyDown
    case keyUp
    case flagsChanged
}

/// 순수 판정 로직. CGEventTap 없이 단위 테스트 가능하다.
enum KeyEventFilter {
    /// 이벤트를 발행할지 판정한다. 자동반복은 무시, 모디파이어는 플래그 전이로 down/up 판정.
    static func decide(
        type: RawKeyEventType,
        keyCode: Int,
        isAutorepeat: Bool,
        previousFlags: UInt64,
        currentFlags: UInt64,
        modifierMask: UInt64
    ) -> KeyEvent? {
        switch type {
        case .keyDown:
            return isAutorepeat ? nil : KeyEvent(keyCode: keyCode, phase: .down)
        case .keyUp:
            return KeyEvent(keyCode: keyCode, phase: .up)
        case .flagsChanged:
            let was = (previousFlags & modifierMask) != 0
            let now = (currentFlags & modifierMask) != 0
            if now && !was { return KeyEvent(keyCode: keyCode, phase: .down) }
            if !now && was { return KeyEvent(keyCode: keyCode, phase: .up) }
            return nil
        }
    }

    /// 모디파이어 키코드 → 해당 CGEventFlags 비트 마스크.
    static func modifierMask(forKeyCode keyCode: Int) -> UInt64? {
        switch keyCode {
        case 56, 60: return CGEventFlags.maskShift.rawValue
        case 59, 62: return CGEventFlags.maskControl.rawValue
        case 58, 61: return CGEventFlags.maskAlternate.rawValue
        case 54, 55: return CGEventFlags.maskCommand.rawValue
        case 57:     return CGEventFlags.maskAlphaShift.rawValue   // caps lock
        case 63:     return CGEventFlags.maskSecondaryFn.rawValue
        default:     return nil
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter KeyEventFilterTests`
Expected: PASS (7개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/KeyEvents/KeyEventFilter.swift Tests/KeyboardSoundTests/KeyEventFilterTests.swift
git commit -m "feat: 자동반복 필터 + 모디파이어 전이 판정 (순수 함수)"
```

---

## Task 4: DSP 프리미티브 (결정적 RNG + 밴드패스 필터)

**Files:**
- Create: `Sources/KeyboardSound/Sound/Random.swift`
- Create: `Sources/KeyboardSound/Sound/Biquad.swift`
- Create: `Tests/KeyboardSoundTests/RandomTests.swift`

**Interfaces:**
- Consumes: (없음)
- Produces:
  - `struct SplitMix64: RandomNumberGenerator { init(seed: UInt64); mutating func next() -> UInt64; mutating func nextUnit() -> Double }`
  - `struct BiquadBandpass { init(sampleRate: Double, centerHz: Double, q: Double); mutating func process(_ x: Float) -> Float }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/RandomTests.swift`:

```swift
import Testing
@testable import KeyboardSound

@Test func sameSeedSameSequence() {
    var a = SplitMix64(seed: 42)
    var b = SplitMix64(seed: 42)
    for _ in 0..<100 { #expect(a.next() == b.next()) }
}

@Test func differentSeedDiffers() {
    var a = SplitMix64(seed: 1)
    var b = SplitMix64(seed: 2)
    #expect(a.next() != b.next())
}

@Test func nextUnitInRange() {
    var r = SplitMix64(seed: 7)
    for _ in 0..<1000 {
        let u = r.nextUnit()
        #expect(u >= 0.0 && u < 1.0)
    }
}

@Test func biquadProducesFiniteOutput() {
    var bp = BiquadBandpass(sampleRate: 44100, centerHz: 2000, q: 4.0)
    var r = SplitMix64(seed: 3)
    for _ in 0..<4410 {
        let y = bp.process(Float(r.nextUnit() * 2 - 1))
        #expect(y.isFinite)
        #expect(abs(y) < 100)   // 발산하지 않음
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter RandomTests`
Expected: FAIL — `SplitMix64`, `BiquadBandpass` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Sound/Random.swift`:

```swift
import Foundation

/// 시드 기반 결정적 의사난수 생성기 (재현성 보장).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 범위의 Double.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
```

`Sources/KeyboardSound/Sound/Biquad.swift`:

```swift
import Foundation

/// RBJ cookbook 기반 2차 밴드패스 필터 (constant skirt gain).
struct BiquadBandpass {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(sampleRate: Double, centerHz: Double, q: Double) {
        let safeQ = max(0.1, q)
        let w0 = 2.0 * Double.pi * centerHz / sampleRate
        let alpha = sin(w0) / (2.0 * safeQ)
        let cosw0 = cos(w0)
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = (-2.0 * cosw0) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let xd = Double(x)
        let y = b0 * xd + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = xd
        y2 = y1; y1 = y
        return Float(y)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter RandomTests`
Expected: PASS (4개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/Random.swift Sources/KeyboardSound/Sound/Biquad.swift Tests/KeyboardSoundTests/RandomTests.swift
git commit -m "feat: 결정적 RNG + 밴드패스 DSP 프리미티브"
```

---

## Task 5: Preset + 파라미터 매핑

**Files:**
- Create: `Sources/KeyboardSound/Sound/Preset.swift`
- Create: `Sources/KeyboardSound/Sound/SoundParameters.swift`
- Create: `Tests/KeyboardSoundTests/PresetTests.swift`

**Interfaces:**
- Consumes: `KeyGroup` (Task 2)
- Produces:
  - `struct SoundParameters: Equatable { var toneFrequency: Double; var sharpness: Double; var decayTime: Double; var bodyMix: Double; var humanization: Double }`
  - `struct Preset: Equatable, Identifiable { let id, name: String; let tone, sharpness, decayTime, bodyMix, humanization: Double; static let clicky/tactile/linear/thock; static let all: [Preset]; static func with(id:) -> Preset? }`
  - `enum SoundParameterMapping { static func toneFrequency(tone: Double, group: KeyGroup) -> Double }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/PresetTests.swift`:

```swift
import Testing
@testable import KeyboardSound

@Test func fourBuiltInPresets() {
    #expect(Preset.all.count == 4)
    #expect(Preset.with(id: "clicky") == .clicky)
    #expect(Preset.with(id: "thock") == .thock)
    #expect(Preset.with(id: "nope") == nil)
}

@Test func clickyBrighterThanThock() {
    #expect(Preset.clicky.tone > Preset.thock.tone)
    #expect(Preset.clicky.sharpness > Preset.thock.sharpness)
}

@Test func higherToneSliderGivesHigherFrequency() {
    let low = SoundParameterMapping.toneFrequency(tone: 0.2, group: .normal)
    let high = SoundParameterMapping.toneFrequency(tone: 0.9, group: .normal)
    #expect(high > low)
}

@Test func wideGroupIsLowerThanNormal() {
    let normal = SoundParameterMapping.toneFrequency(tone: 0.5, group: .normal)
    let wide = SoundParameterMapping.toneFrequency(tone: 0.5, group: .wide)
    #expect(wide < normal)
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter PresetTests`
Expected: FAIL — `Preset`, `SoundParameters`, `SoundParameterMapping` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Sound/SoundParameters.swift`:

```swift
import Foundation

/// 합성기에 전달되는 실제 DSP 파라미터.
struct SoundParameters: Equatable {
    var toneFrequency: Double   // Hz, 클릭 중심 주파수
    var sharpness: Double       // 0...1 (어택 가파름 + 노이즈량)
    var decayTime: Double       // 초
    var bodyMix: Double         // 0...1 (바디:노이즈 비율)
    var humanization: Double    // 0...1 (변형 피치 지터 폭)
}
```

`Sources/KeyboardSound/Sound/Preset.swift`:

```swift
import Foundation

/// 스위치 느낌 프리셋. tone/sharpness는 슬라이더 기본값(0...1),
/// decayTime/bodyMix/humanization은 비노출 내부값.
struct Preset: Equatable, Identifiable {
    let id: String
    let name: String
    let tone: Double
    let sharpness: Double
    let decayTime: Double
    let bodyMix: Double
    let humanization: Double

    static let clicky  = Preset(id: "clicky",  name: "Clicky",  tone: 0.78, sharpness: 0.85, decayTime: 0.045, bodyMix: 0.25, humanization: 0.15)
    static let tactile = Preset(id: "tactile", name: "Tactile", tone: 0.55, sharpness: 0.60, decayTime: 0.060, bodyMix: 0.45, humanization: 0.20)
    static let linear  = Preset(id: "linear",  name: "Linear",  tone: 0.50, sharpness: 0.35, decayTime: 0.050, bodyMix: 0.55, humanization: 0.15)
    static let thock   = Preset(id: "thock",   name: "Thock",   tone: 0.25, sharpness: 0.30, decayTime: 0.090, bodyMix: 0.70, humanization: 0.25)

    static let all: [Preset] = [.clicky, .tactile, .linear, .thock]

    static func with(id: String) -> Preset? {
        all.first { $0.id == id }
    }
}

/// tone/sharpness 슬라이더(0...1) → 합성 파라미터 변환.
enum SoundParameterMapping {
    /// tone 슬라이더(0...1)를 로그 스케일 주파수로. wide 그룹은 한 옥타브 낮춤.
    static func toneFrequency(tone: Double, group: KeyGroup) -> Double {
        let minHz = 600.0
        let maxHz = 4000.0
        let base = minHz * pow(maxHz / minHz, max(0, min(1, tone)))
        return group == .wide ? base * 0.5 : base
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter PresetTests`
Expected: PASS (4개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/Preset.swift Sources/KeyboardSound/Sound/SoundParameters.swift Tests/KeyboardSoundTests/PresetTests.swift
git commit -m "feat: Preset 4종 + tone/그룹→주파수 매핑"
```

---

## Task 6: ClickSynth (순수 합성)

**Files:**
- Create: `Sources/KeyboardSound/Sound/ClickSynth.swift`
- Create: `Tests/KeyboardSoundTests/ClickSynthTests.swift`

**Interfaces:**
- Consumes: `SoundParameters` (Task 5), `KeyPhase` (Task 2), `SplitMix64`, `BiquadBandpass` (Task 4)
- Produces:
  - `struct ClickSynth { init(sampleRate: Double); func render(parameters: SoundParameters, phase: KeyPhase, pitchMultiplier: Double, seed: UInt64) -> [Float] }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/ClickSynthTests.swift`:

```swift
import Testing
import Foundation
@testable import KeyboardSound

private let params = SoundParameters(toneFrequency: 2000, sharpness: 0.7,
                                     decayTime: 0.05, bodyMix: 0.4, humanization: 0.2)

@Test func renderIsNotSilent() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    let rms = sqrt(s.reduce(0) { $0 + Double($1 * $1) } / Double(s.count))
    #expect(rms > 0.001)
}

@Test func renderLengthMatchesDecay() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    // 0.05s * 44100 ≈ 2205 samples
    #expect(s.count >= 2000 && s.count <= 2400)
}

@Test func sameSeedSameOutput() {
    let synth = ClickSynth(sampleRate: 44100)
    let a = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 99)
    let b = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 99)
    #expect(a == b)
}

@Test func upIsShorterThanDown() {
    let synth = ClickSynth(sampleRate: 44100)
    let down = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 1)
    let up = synth.render(parameters: params, phase: .up, pitchMultiplier: 1.0, seed: 1)
    #expect(up.count < down.count)
}

@Test func outputIsBounded() {
    let synth = ClickSynth(sampleRate: 44100)
    let s = synth.render(parameters: params, phase: .down, pitchMultiplier: 1.0, seed: 5)
    for v in s {
        #expect(v.isFinite)
        #expect(v >= -1.0 && v <= 1.0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ClickSynthTests`
Expected: FAIL — `ClickSynth` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Sound/ClickSynth.swift`:

```swift
import Foundation

/// 파라미터로부터 기계식 클릭음 PCM 샘플([Float])을 절차적으로 합성한다. 순수 함수.
struct ClickSynth {
    let sampleRate: Double

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

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

            var s = (noise * noiseMix + body * bodyMix) * env * amplitude
            s = max(-1.0, min(1.0, s))   // 소프트 클램프
            out[n] = s
        }
        return out
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ClickSynthTests`
Expected: PASS (5개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/ClickSynth.swift Tests/KeyboardSoundTests/ClickSynthTests.swift
git commit -m "feat: 절차적 클릭음 합성기 (순수 DSP)"
```

---

## Task 7: ClickSoundBank (사전 렌더 + 버퍼 선택)

**Files:**
- Create: `Sources/KeyboardSound/Sound/ClickSoundBank.swift`
- Create: `Tests/KeyboardSoundTests/ClickSoundBankTests.swift`

**Interfaces:**
- Consumes: `ClickSynth` (Task 6), `Preset`, `SoundParameters`, `SoundParameterMapping` (Task 5), `KeyGroupMap`, `KeyPhase` (Task 2)
- Produces:
  - `final class ClickSoundBank { init(format: AVAudioFormat, tone: Double, sharpness: Double, preset: Preset, variantCount: Int = 6); func regenerate(tone: Double, sharpness: Double, preset: Preset); func buffer(forKeyCode: Int, phase: KeyPhase) -> AVAudioPCMBuffer }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/ClickSoundBankTests.swift`:

```swift
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
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ClickSoundBankTests`
Expected: FAIL — `ClickSoundBank` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Sound/ClickSoundBank.swift`:

```swift
import AVFoundation

/// 그룹/페이즈별 변형 버퍼를 사전 렌더하고, keyCode로 적절한 버퍼를 선택한다.
final class ClickSoundBank {
    private let format: AVAudioFormat
    private let sampleRate: Double
    private let variantCount: Int

    private var buffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]] = [:]
    private var pressCounters: [Int: Int] = [:]

    init(format: AVAudioFormat, tone: Double, sharpness: Double, preset: Preset, variantCount: Int = 6) {
        self.format = format
        self.sampleRate = format.sampleRate
        self.variantCount = max(1, variantCount)
        regenerate(tone: tone, sharpness: sharpness, preset: preset)
    }

    /// 파라미터 변경 시 전체 버퍼 재생성.
    func regenerate(tone: Double, sharpness: Double, preset: Preset) {
        let synth = ClickSynth(sampleRate: sampleRate)
        var newBuffers: [KeyGroup: [KeyPhase: [AVAudioPCMBuffer]]] = [:]

        for group in [KeyGroup.normal, .wide] {
            let toneFreq = SoundParameterMapping.toneFrequency(tone: tone, group: group)
            let params = SoundParameters(
                toneFrequency: toneFreq,
                sharpness: sharpness,
                decayTime: preset.decayTime,
                bodyMix: preset.bodyMix,
                humanization: preset.humanization
            )

            var byPhase: [KeyPhase: [AVAudioPCMBuffer]] = [:]
            for phase in [KeyPhase.down, .up] {
                var variants: [AVAudioPCMBuffer] = []
                for i in 0..<variantCount {
                    // (group, phase, i) 결정적 시드
                    let groupComponent = UInt64(group == .wide ? 1 : 0) &* 1_000_003
                    let phaseComponent = UInt64(phase == .up ? 1 : 0) &* 7_919
                    let seed = groupComponent &+ phaseComponent &+ UInt64(i) &* 104_729 &+ 0xABCDEF

                    // 변형마다 미세 피치 지터 (휴머나이즈)
                    let spread = (Double(i) / Double(max(1, variantCount - 1))) - 0.5
                    let pitchMul = 1.0 + spread * 2.0 * params.humanization * 0.1

                    let samples = synth.render(parameters: params, phase: phase, pitchMultiplier: pitchMul, seed: seed)
                    variants.append(Self.makeBuffer(samples: samples, format: format))
                }
                byPhase[phase] = variants
            }
            newBuffers[group] = byPhase
        }
        buffers = newBuffers
    }

    /// keyCode와 페이즈로 버퍼 선택. down일 때 키별 카운터를 올려 변형을 순환시킨다.
    func buffer(forKeyCode keyCode: Int, phase: KeyPhase) -> AVAudioPCMBuffer {
        let group = KeyGroupMap.group(for: keyCode)
        let count = pressCounters[keyCode, default: 0]
        if phase == .down {
            pressCounters[keyCode] = count + 1
        }
        let index = abs(keyCode + count) % variantCount
        // 그룹/페이즈 버퍼는 init/regenerate에서 항상 채워지므로 강제 언랩 안전.
        return buffers[group]![phase]![index]
    }

    private static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }
        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            let dst = channels[ch]
            for i in 0..<samples.count { dst[i] = samples[i] }
        }
        return buffer
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ClickSoundBankTests`
Expected: PASS (5개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/ClickSoundBank.swift Tests/KeyboardSoundTests/ClickSoundBankTests.swift
git commit -m "feat: 사운드 뱅크 — 사전 렌더 + 그룹/변형 버퍼 선택"
```

---

## Task 8: Settings (UserDefaults 영속화)

**Files:**
- Create: `Sources/KeyboardSound/Settings/Settings.swift`
- Create: `Tests/KeyboardSoundTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `Preset` (Task 5)
- Produces:
  - `final class Settings: ObservableObject { @Published var enabled: Bool; @Published var presetID: String; @Published var volume: Double; @Published var tone: Double; @Published var sharpness: Double; init(defaults: UserDefaults = .standard); func applyPreset(_ preset: Preset); func userAdjustedTone(_ v: Double); func userAdjustedSharpness(_ v: Double); var currentPreset: Preset }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/SettingsTests.swift`:

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
    #expect(s.presetID == "clicky")
    #expect(s.volume > 0 && s.volume <= 1)
}

@Test func persistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.volume = 0.33
    s1.presetID = "thock"
    let s2 = Settings(defaults: d)
    #expect(abs(s2.volume - 0.33) < 0.0001)
    #expect(s2.presetID == "thock")
}

@Test func applyPresetSetsToneAndSharpness() {
    let s = Settings(defaults: freshDefaults())
    s.applyPreset(.thock)
    #expect(s.presetID == "thock")
    #expect(abs(s.tone - Preset.thock.tone) < 0.0001)
    #expect(abs(s.sharpness - Preset.thock.sharpness) < 0.0001)
}

@Test func userAdjustingSliderSwitchesToCustom() {
    let s = Settings(defaults: freshDefaults())
    s.applyPreset(.clicky)
    s.userAdjustedTone(0.1)
    #expect(s.presetID == "custom")
    #expect(abs(s.tone - 0.1) < 0.0001)
}

@Test func currentPresetFallsBackToClicky() {
    let s = Settings(defaults: freshDefaults())
    s.presetID = "custom"
    #expect(s.currentPreset == .clicky)   // custom일 때 내부값은 clicky 폴백
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SettingsTests`
Expected: FAIL — `Settings` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Settings/Settings.swift`:

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SettingsTests`
Expected: PASS (5개).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Settings/Settings.swift Tests/KeyboardSoundTests/SettingsTests.swift
git commit -m "feat: Settings — UserDefaults 영속화 + 프리셋/슬라이더 로직"
```

---

## Task 9: SoundPlaying 프로토콜 + SoundPlayer (오디오 엔진)

**Files:**
- Create: `Sources/KeyboardSound/Sound/SoundPlayer.swift`

**Interfaces:**
- Consumes: (없음, AVFoundation)
- Produces:
  - `protocol SoundPlaying: AnyObject { func play(_ buffer: AVAudioPCMBuffer, volume: Float) }`
  - `final class SoundPlayer: SoundPlaying { init(poolSize: Int = 8, sampleRate: Double = 44100); let format: AVAudioFormat; func start() throws; func stop(); func play(_ buffer: AVAudioPCMBuffer, volume: Float) }`

> 시스템 오디오 의존이라 단위 테스트 대신 수동 검증. 다음 태스크들이 `format`과 `SoundPlaying`을 사용한다.

- [ ] **Step 1: 구현**

`Sources/KeyboardSound/Sound/SoundPlayer.swift`:

```swift
import AVFoundation

/// 버퍼 재생 추상화. 테스트에서 스파이로 대체 가능.
protocol SoundPlaying: AnyObject {
    func play(_ buffer: AVAudioPCMBuffer, volume: Float)
}

/// AVAudioEngine + 플레이어 노드 풀(라운드로빈)로 겹치는 클릭음을 저지연 재생.
final class SoundPlayer: SoundPlaying {
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextIndex = 0

    init(poolSize: Int = 8, sampleRate: Double = 44100) {
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        for _ in 0..<max(1, poolSize) {
            let node = AVAudioPlayerNode()
            players.append(node)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    func start() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
        players.forEach { $0.play() }
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
    }

    func play(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard engine.isRunning else { return }
        let node = players[nextIndex]
        nextIndex = (nextIndex + 1) % players.count
        node.volume = max(0, min(1, volume))
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/KeyboardSound/Sound/SoundPlayer.swift
git commit -m "feat: SoundPlaying 프로토콜 + AVAudioEngine 풀 재생기"
```

---

## Task 10: KeySoundController (조율자)

**Files:**
- Create: `Sources/KeyboardSound/Coordinator/KeySoundController.swift`
- Create: `Tests/KeyboardSoundTests/KeySoundControllerTests.swift`

**Interfaces:**
- Consumes: `Settings` (Task 8), `ClickSoundBank` (Task 7), `SoundPlaying` (Task 9), `KeyEvent` (Task 2)
- Produces:
  - `final class KeySoundController { init(settings: Settings, bank: ClickSoundBank, player: SoundPlaying); func handle(_ event: KeyEvent) }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeyboardSoundTests/KeySoundControllerTests.swift`:

```swift
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
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter KeySoundControllerTests`
Expected: FAIL — `KeySoundController` 미정의.

- [ ] **Step 3: 구현**

`Sources/KeyboardSound/Coordinator/KeySoundController.swift`:

```swift
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter KeySoundControllerTests`
Expected: PASS (3개).

- [ ] **Step 5: 전체 테스트 실행**

Run: `swift test`
Expected: 전체 PASS (Task 2–10 누적).

- [ ] **Step 6: 커밋**

```bash
git add Sources/KeyboardSound/Coordinator Tests/KeyboardSoundTests/KeySoundControllerTests.swift
git commit -m "feat: KeySoundController — enabled 게이트 + 볼륨 전달"
```

---

## Task 11: AccessibilityPermission 헬퍼

**Files:**
- Create: `Sources/KeyboardSound/Permissions/AccessibilityPermission.swift`

**Interfaces:**
- Consumes: (없음)
- Produces:
  - `enum AccessibilityPermission { static var isTrusted: Bool; static func promptIfNeeded(); static func openSettings() }`

> 시스템 권한 의존 → 수동 검증.

- [ ] **Step 1: 구현**

`Sources/KeyboardSound/Permissions/AccessibilityPermission.swift`:

```swift
import AppKit
import ApplicationServices

/// 손쉬운 사용(Accessibility) 권한 확인/안내.
enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 미허가 시 시스템 권한 요청 다이얼로그를 띄운다.
    static func promptIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 시스템 설정의 손쉬운 사용 패널을 연다.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/KeyboardSound/Permissions
git commit -m "feat: Accessibility 권한 확인/안내 헬퍼"
```

---

## Task 12: KeyEventMonitor (CGEventTap)

**Files:**
- Create: `Sources/KeyboardSound/KeyEvents/KeyEventMonitor.swift`

**Interfaces:**
- Consumes: `KeyEventFilter`, `RawKeyEventType` (Task 3), `KeyEvent` (Task 2)
- Produces:
  - `final class KeyEventMonitor { enum Status { case inactive, active, permissionDenied }; var onEvent: ((KeyEvent) -> Void)?; private(set) var status: Status; @discardableResult func start() -> Status; func stop() }`

> CGEventTap + 권한 의존 → 수동 검증.

- [ ] **Step 1: 구현**

`Sources/KeyboardSound/KeyEvents/KeyEventMonitor.swift`:

```swift
import CoreGraphics
import Foundation

/// CGEventTap(듣기 전용)으로 전역 키 이벤트를 받아 필터링 후 onEvent로 발행한다.
final class KeyEventMonitor {
    enum Status {
        case inactive
        case active
        case permissionDenied
    }

    var onEvent: ((KeyEvent) -> Void)?
    private(set) var status: Status = .inactive

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: UInt64 = 0

    @discardableResult
    func start() -> Status {
        guard tap == nil else { return status }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = .permissionDenied
            return status
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = .active
        return status
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
        status = .inactive
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // 시스템이 탭을 끈 경우 재활성화.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let currentFlags = event.flags.rawValue

        let rawType: RawKeyEventType
        var modifierMask: UInt64 = 0
        switch type {
        case .keyDown:
            rawType = .keyDown
        case .keyUp:
            rawType = .keyUp
        case .flagsChanged:
            rawType = .flagsChanged
            modifierMask = KeyEventFilter.modifierMask(forKeyCode: keyCode) ?? 0
        default:
            return
        }

        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let result = KeyEventFilter.decide(
            type: rawType,
            keyCode: keyCode,
            isAutorepeat: isAutorepeat,
            previousFlags: previousFlags,
            currentFlags: currentFlags,
            modifierMask: modifierMask
        )

        if type == .flagsChanged {
            previousFlags = currentFlags
        }
        if let result {
            onEvent?(result)
        }
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/KeyboardSound/KeyEvents/KeyEventMonitor.swift
git commit -m "feat: CGEventTap 전역 키 모니터 (듣기 전용 + 탭 재활성화)"
```

---

## Task 13: 메뉴바 + 설정 창 UI

**Files:**
- Create: `Sources/KeyboardSound/UI/SettingsView.swift`
- Create: `Sources/KeyboardSound/UI/SettingsWindowController.swift`
- Create: `Sources/KeyboardSound/UI/StatusMenuController.swift`

**Interfaces:**
- Consumes: `Settings` (Task 8), `Preset` (Task 5)
- Produces:
  - `struct SettingsView: View { init(settings: Settings, onTest: @escaping () -> Void) }`
  - `final class SettingsWindowController { init(settings: Settings, onTest: @escaping () -> Void); func show() }`
  - `final class StatusMenuController: NSObject { init(settings: Settings, onOpenSettings: @escaping () -> Void, onOpenPermission: @escaping () -> Void); func setPermissionDenied(_ denied: Bool) }`

> AppKit/SwiftUI UI → 수동 검증.

- [ ] **Step 1: SwiftUI 설정 뷰 구현**

`Sources/KeyboardSound/UI/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let onTest: () -> Void

    init(settings: Settings, onTest: @escaping () -> Void) {
        self.settings = settings
        self.onTest = onTest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyboardSound")
                .font(.headline)

            Picker("프리셋", selection: Binding(
                get: { settings.presetID },
                set: { id in
                    if let preset = Preset.with(id: id) { settings.applyPreset(preset) }
                }
            )) {
                ForEach(Preset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                if settings.presetID == "custom" {
                    Text("Custom").tag("custom")
                }
            }
            .pickerStyle(.segmented)

            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            slider("톤",   value: Binding(get: { settings.tone }, set: { settings.userAdjustedTone($0) }))
            slider("샤프함", value: Binding(get: { settings.sharpness }, set: { settings.userAdjustedSharpness($0) }))

            Button("테스트 소리", action: onTest)
        }
        .padding(20)
        .frame(width: 320)
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}
```

- [ ] **Step 2: 설정 창 컨트롤러 구현**

`Sources/KeyboardSound/UI/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// SettingsView를 NSWindow에 호스팅한다.
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let onTest: () -> Void

    init(settings: Settings, onTest: @escaping () -> Void) {
        self.settings = settings
        self.onTest = onTest
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, onTest: onTest)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "KeyboardSound 설정"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: 메뉴바 컨트롤러 구현**

`Sources/KeyboardSound/UI/StatusMenuController.swift`:

```swift
import AppKit

/// 메뉴바 아이콘 + 메뉴. 켜기/끄기, 프리셋, 설정 창, 권한 상태, 종료.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let onOpenSettings: () -> Void
    private let onOpenPermission: () -> Void

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var permissionDenied = false

    init(settings: Settings,
         onOpenSettings: @escaping () -> Void,
         onOpenPermission: @escaping () -> Void) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onOpenPermission = onOpenPermission
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyboardSound")
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    func setPermissionDenied(_ denied: Bool) {
        permissionDenied = denied
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        if permissionDenied {
            let item = NSMenuItem(title: "⚠️ 손쉬운 사용 권한 필요 — 설정 열기",
                                  action: #selector(openPermission), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: "소리 켜기", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)

        let presetMenu = NSMenu()
        for preset in Preset.all {
            let item = NSMenuItem(title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = (settings.presetID == preset.id) ? .on : .off
            presetMenu.addItem(item)
        }
        let presetParent = NSMenuItem(title: "프리셋", action: nil, keyEquivalent: "")
        menu.setSubmenu(presetMenu, for: presetParent)
        menu.addItem(presetParent)

        let settingsItem = NSMenuItem(title: "사운드 설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { settings.enabled.toggle(); rebuild() }
    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let preset = Preset.with(id: id) {
            settings.applyPreset(preset)
        }
        rebuild()
    }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openPermission() { onOpenPermission() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/UI
git commit -m "feat: 메뉴바 컨트롤러 + SwiftUI 설정 창"
```

---

## Task 14: AppDelegate + 진입점 와이어링

**Files:**
- Create: `Sources/KeyboardSound/App/AppDelegate.swift`
- Modify: `Sources/KeyboardSound/main.swift` (스텁 교체)

**Interfaces:**
- Consumes: 모든 이전 컴포넌트
- Produces: 실행 가능한 메뉴바 앱

> 전체 와이어링 + 런타임 → 수동 검증.

- [ ] **Step 1: AppDelegate 구현**

`Sources/KeyboardSound/App/AppDelegate.swift`:

```swift
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let player = SoundPlayer()
    private let monitor = KeyEventMonitor()

    private var bank: ClickSoundBank!
    private var controller: KeySoundController!
    private var menuController: StatusMenuController!
    private var settingsWindow: SettingsWindowController!

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bank = ClickSoundBank(format: player.format,
                              tone: settings.tone,
                              sharpness: settings.sharpness,
                              preset: settings.currentPreset)
        controller = KeySoundController(settings: settings, bank: bank, player: player)
        monitor.onEvent = { [weak self] event in self?.controller.handle(event) }

        settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
            self?.playTestSound()
        }
        menuController = StatusMenuController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onOpenPermission: { AccessibilityPermission.openSettings() }
        )

        // 톤/샤프함/프리셋 변경 → 뱅크 재생성
        settings.$tone
            .combineLatest(settings.$sharpness, settings.$presetID)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.regenerateBank() }
            .store(in: &cancellables)

        // enabled 변경 → 시작/정지
        settings.$enabled
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.promptIfNeeded()
        }
        setEnabled(settings.enabled)
        startPermissionWatcher()
    }

    private func regenerateBank() {
        bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, preset: settings.currentPreset)
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            try? player.start()
            let status = monitor.start()
            menuController?.setPermissionDenied(status == .permissionDenied)
        } else {
            monitor.stop()
            player.stop()
        }
    }

    private func playTestSound() {
        guard settings.enabled, AccessibilityPermission.isTrusted else { return }
        controller.handle(KeyEvent(keyCode: 0, phase: .down))
    }

    /// 미허가 동안 권한을 폴링해 부여되면 자동 활성화.
    private func startPermissionWatcher() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let denied = !AccessibilityPermission.isTrusted
            self.menuController?.setPermissionDenied(denied)
            if !denied, self.settings.enabled, self.monitor.status != .active {
                _ = self.monitor.start()
            }
        }
    }
}
```

- [ ] **Step 2: 진입점 교체**

`Sources/KeyboardSound/main.swift` (전체 교체):

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 메뉴바 전용 (Dock 아이콘 없음)
app.run()
```

- [ ] **Step 3: 빌드 + 전체 테스트**

Run: `swift build && swift test`
Expected: 빌드 성공, 모든 단위 테스트 PASS.

- [ ] **Step 4: 커밋**

```bash
git add Sources/KeyboardSound/App Sources/KeyboardSound/main.swift
git commit -m "feat: AppDelegate 와이어링 + 메뉴바 앱 진입점"
```

---

## Task 15: .app 번들 빌드 스크립트 + README + 종단 검증

**Files:**
- Create: `scripts/build-app.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: 빌드 산출물
- Produces: 실행 가능한 `KeyboardSound.app`

- [ ] **Step 1: 빌드 스크립트 작성**

`scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="KeyboardSound"
BUNDLE_ID="com.keyboardsound.app"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"

echo "==> swift build (release)"
swift build -c release

echo "==> .app 번들 조립"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 코드 서명"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> 완료: ${APP_DIR}"
echo "실행: open ${APP_DIR}  (첫 실행 시 손쉬운 사용 권한 부여 필요)"
```

- [ ] **Step 2: 스크립트 실행 권한 + 실행**

Run:
```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```
Expected: `KeyboardSound.app` 생성, codesign 성공, "완료" 출력.

- [ ] **Step 3: README 작성**

`README.md`:

```markdown
# KeyboardSound

맥에서 키 입력마다 합성된 기계식 키보드 클릭음을 내는 메뉴바 앱.

## 빌드

\`\`\`bash
./scripts/build-app.sh
\`\`\`

## 실행

\`\`\`bash
open KeyboardSound.app
\`\`\`

첫 실행 시 **시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용**에서 KeyboardSound를 허용해야 키 입력이 감지됩니다.
메뉴바의 키보드 아이콘에서 켜기/끄기, 프리셋(Clicky/Tactile/Linear/Thock), "사운드 설정…"(볼륨·톤·샤프함)을 조절할 수 있습니다.

## 개발

\`\`\`bash
swift build      # 빌드
swift test       # 단위 테스트
\`\`\`

## 사운드

모든 소리는 코드로 합성되며(녹음 샘플 미사용) 저작권 부담 없이 자유롭게 배포할 수 있습니다.

## 정식 배포 (추후)

남에게 배포하려면 ad-hoc 서명 대신 Apple Developer ID 서명 + 공증(notarization)이 필요합니다.
```

- [ ] **Step 4: 종단 수동 검증**

`KeyboardSound.app` 실행 후 확인:
1. 메뉴바에 키보드 아이콘 표시 (Dock 아이콘 없음)
2. 손쉬운 사용 권한 부여 → 재시작 없이 자동 활성화 (최대 2초)
3. 타이핑 시 소리, 끄기 시 무음
4. 프리셋/슬라이더 변경 시 소리 변화 (Thock은 낮고 묵직)
5. 빠른 연타 시 겹침 재생, 글리치 없음
6. 키 꾹 누름 시 단발 소리 (연사 없음)
7. Space/Enter/모디파이어 → thock 소리

- [ ] **Step 5: 커밋**

```bash
git add scripts/build-app.sh README.md
git commit -m "feat: .app 번들 빌드 스크립트 + README"
```

---

## Self-Review 결과

**1. Spec coverage** — spec 각 섹션 대응:
- §4.3 KeyEventMonitor → Task 12 (필터는 Task 3)
- §4.4 ClickSoundBank/합성 → Task 4(프리미티브), 6(합성), 7(뱅크)
- §4.5 SoundPlayer → Task 9
- §4.6 Settings/Preset → Task 5, 8
- §4.7 패키징 → Task 1, 15
- §5 권한 UX → Task 11, 14(워처), 13(메뉴 표시)
- §6 메뉴바/설정 창 → Task 13
- §7 에러 처리 → Task 9(엔진 try), 12(탭 재활성화), 6(클램프)
- §8 테스트 → Task 2,3,4,5,6,7,8,10 단위 + Task 15 수동
- 모든 spec 요구사항에 대응 태스크 존재. 갭 없음.

**2. Placeholder scan** — "TBD/TODO/적절히 처리" 없음. 모든 코드 스텝에 완전한 코드 포함.

**3. Type consistency** — `KeyEvent(keyCode:phase:)`, `KeyPhase{.down,.up}`, `KeyGroup{.normal,.wide}`, `KeyGroupMap.group(for:)`, `KeyEventFilter.decide(...)`/`.modifierMask(forKeyCode:)`, `SoundParameters` 필드, `Preset` 필드/`with(id:)`/`all`, `ClickSynth.render(parameters:phase:pitchMultiplier:seed:)`, `ClickSoundBank.init/regenerate/buffer(forKeyCode:phase:)`, `Settings` 프로퍼티/메서드, `SoundPlaying.play(_:volume:)`, `SoundPlayer.format/start/stop`, `KeySoundController.handle(_:)` — 태스크 간 시그니처 일관됨. 불일치 없음.
