# 커스텀 오디오 샘플 타건음 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사용자가 고른 오디오 파일을, 새 프리셋 "커스텀 샘플"로 선택했을 때 키를 누를 때마다(down) 모노폰으로 재생한다.

**Architecture:** 합성 경로(`ClickSynth`/`ClickSoundBank`/`SoundPlayer`)는 전혀 손대지 않는다. 커스텀 디코딩은 신규 `CustomSampleStore`, 모노폰 재생은 자체 엔진을 가진 신규 `SamplePlayer`에 격리한다. `KeySoundController`가 `selectedSwitchID == "custom"`일 때만 커스텀 경로로 분기한다(완전 추가형).

**Tech Stack:** Swift / AVFoundation (AVAudioFile, AVAudioConverter, AVAudioEngine, AVAudioPlayerNode) / SwiftUI + AppKit(NSOpenPanel) / Swift Testing.

## Global Constraints

- Swift tools 6.0, `swiftLanguageModes: [.v5]`, 플랫폼 `macOS(.v13)` — `Package.swift` 변경 금지.
- 테스트 프레임워크: **Swift Testing** (`import Testing`, `@Test func`). XCTest 사용 금지.
- 엔진/디코딩 타깃 포맷: `AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)`.
- **완전 추가형(additive-only).** 합성음 동작·슬라이더·영속화·권한 흐름은 코드/동작 모두 불변.
- **기존 파일 절대 손대지 않음**: `Sound/ClickSynth.swift`, `Sound/ClickSoundBank.swift`, `Sound/SoundPlayer.swift`, `Sound/SoundParameters.swift`, `Sound/Biquad.swift`, `KeyEvents/*`, 그리고 **기존 8개 테스트 파일 전부**. 새 테스트는 **신규 파일**로만 추가한다.
- 커스텀 프리셋 id 문자열은 정확히 `"custom"`. `Preset.all`(4개)에 추가하지 않는다.
- 빌드/테스트 명령: `swift build`, `swift test`.
- 메인 스레드 계약: 오디오 재생/뱅크 접근은 메인 스레드 전용(기존과 동일).

---

### Task 1: `Preset.customID` 상수

**Files:**
- Modify: `Sources/KeyboardSound/Sound/Preset.swift`
- Test: `Tests/KeyboardSoundTests/CustomPresetTests.swift` (Create)

**Interfaces:**
- Consumes: 없음
- Produces: `Preset.customID: String == "custom"` — Task 4·5·6·8·9에서 사용.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/KeyboardSoundTests/CustomPresetTests.swift`:

```swift
import Testing
@testable import KeyboardSound

@Test func customIDIsStable() {
    #expect(Preset.customID == "custom")
}

@Test func customIDIsNotASynthPreset() {
    #expect(Preset.with(id: Preset.customID) == nil)
    #expect(Preset.all.count == 4)
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter CustomPresetTests`
Expected: 컴파일 실패 — `customID` 멤버 없음.

- [ ] **Step 3: 최소 구현**

`Sources/KeyboardSound/Sound/Preset.swift`에서 `static let all` 줄 바로 아래에 추가:

```swift
    static let all: [Preset] = [.blue, .brown, .red, .topre]

    /// 커스텀 샘플 프리셋 식별자. `Preset.all`에는 포함하지 않는다(합성 4종 불변).
    static let customID = "custom"
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter CustomPresetTests`
Expected: PASS (2 tests).

- [ ] **Step 5: 회귀 확인 + 커밋**

```bash
swift test --filter PresetTests
git add Sources/KeyboardSound/Sound/Preset.swift Tests/KeyboardSoundTests/CustomPresetTests.swift
git commit -m "feat: Preset.customID 상수 추가 (Preset.all 불변)"
```
Expected: 기존 `PresetTests` 그대로 PASS.

---

### Task 2: `CustomSampleStore` — 파일 디코딩

**Files:**
- Create: `Sources/KeyboardSound/Sound/CustomSampleStore.swift`
- Test: `Tests/KeyboardSoundTests/CustomSampleStoreTests.swift` (Create)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `protocol SampleProviding: AnyObject { var buffer: AVAudioPCMBuffer? { get } }` — Task 6에서 사용.
  - `final class CustomSampleStore: ObservableObject, SampleProviding`
    - `init(format: AVAudioFormat, directory: URL = CustomSampleStore.defaultDirectory, defaults: UserDefaults = .standard)`
    - `@Published private(set) var fileName: String?`
    - `private(set) var buffer: AVAudioPCMBuffer?`
    - `func importFile(_ url: URL) throws`
    - `func loadPersisted()` (Task 3에서 구현)
    - `static var defaultDirectory: URL`
  - Task 7·9에서 사용.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/KeyboardSoundTests/CustomSampleStoreTests.swift`:

```swift
import Testing
import AVFoundation
@testable import KeyboardSound

private let engineFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("css-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "css-\(UUID().uuidString)")!
}

/// 48kHz 모노 WAV fixture — 디코딩 시 44.1kHz 스테레오로의 리샘플/채널 변환 경로를 강제.
private func writeFixtureWAV(seconds: Double = 0.1, sampleRate: Double = 48000) -> URL {
    let url = tempDir().appendingPathComponent("fixture.wav")
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try! AVAudioFile(forWriting: url, settings: fmt.settings)
    let frames = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    let ch = buf.floatChannelData![0]
    for i in 0..<Int(frames) { ch[i] = sinf(Float(i) * 0.05) * 0.5 }
    try! file.write(from: buf)
    return url
}

@Test func importDecodesToEngineFormat() throws {
    let src = writeFixtureWAV()
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    try store.importFile(src)
    let buf = try #require(store.buffer)
    #expect(buf.frameLength > 0)
    #expect(buf.format.sampleRate == 44100)
    #expect(buf.format.channelCount == 2)
    #expect(store.fileName == "fixture.wav")
}

@Test func importBadFileThrows() {
    let bad = tempDir().appendingPathComponent("not-audio.wav")
    try! Data([0x00, 0x01, 0x02, 0x03]).write(to: bad)
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    #expect(throws: (any Error).self) { try store.importFile(bad) }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter CustomSampleStoreTests`
Expected: 컴파일 실패 — `CustomSampleStore` 없음.

- [ ] **Step 3: 최소 구현**

Create `Sources/KeyboardSound/Sound/CustomSampleStore.swift`:

```swift
import AVFoundation
import os

private let storeLog = Logger(subsystem: "com.keyboardsound.app", category: "sample")

/// 컨트롤러가 의존하는 버퍼 공급 추상화(테스트에서 스텁으로 대체 가능).
protocol SampleProviding: AnyObject {
    var buffer: AVAudioPCMBuffer? { get }
}

/// 사용자 오디오 파일을 앱 폴더로 복사·디코딩·영속화한다. 메인 스레드 전용.
final class CustomSampleStore: ObservableObject, SampleProviding {
    private enum Keys {
        static let path = "customSamplePath"
        static let name = "customSampleName"
    }

    @Published private(set) var fileName: String?
    private(set) var buffer: AVAudioPCMBuffer?

    private let format: AVAudioFormat
    private let directory: URL
    private let defaults: UserDefaults

    init(format: AVAudioFormat,
         directory: URL = CustomSampleStore.defaultDirectory,
         defaults: UserDefaults = .standard) {
        self.format = format
        self.directory = directory
        self.defaults = defaults
        self.fileName = defaults.string(forKey: Keys.name)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyboardSound", isDirectory: true)
    }

    /// 파일 복사 + 디코딩 + 경로/이름 영속화. 디코딩 실패 시 throw하고 상태는 바뀌지 않는다.
    func importFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let dst = directory.appendingPathComponent("custom-sample.\(ext)")
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: url, to: dst)

        // 디코딩 먼저 — 실패하면 복사본 정리하고 throw(이전 상태 유지).
        let decoded: AVAudioPCMBuffer
        do {
            decoded = try Self.decode(url: dst, to: format)
        } catch {
            try? FileManager.default.removeItem(at: dst)
            throw error
        }

        // 성공: 이전 복사본 제거 후 새 상태 커밋.
        if let old = defaults.string(forKey: Keys.path), old != dst.path {
            try? FileManager.default.removeItem(atPath: old)
        }
        buffer = decoded
        fileName = url.lastPathComponent
        defaults.set(dst.path, forKey: Keys.path)
        defaults.set(url.lastPathComponent, forKey: Keys.name)
    }

    /// 파일을 target 포맷의 PCM 버퍼로 디코딩(필요 시 리샘플/채널 변환).
    static func decode(url: URL, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let srcBuffer = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else {
            throw NSError(domain: "CustomSampleStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "empty or unreadable audio"])
        }
        try file.read(into: srcBuffer)

        if src == target { return srcBuffer }

        guard let converter = AVAudioConverter(from: src, to: target) else {
            throw NSError(domain: "CustomSampleStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no converter"])
        }
        let ratio = target.sampleRate / src.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 4096
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw NSError(domain: "CustomSampleStore", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "alloc failed"])
        }
        var fed = false
        var convError: NSError?
        let status = converter.convert(to: dstBuffer, error: &convError) { _, outStatus in
            if fed { outStatus.pointee = .endOfStream; return nil }
            fed = true
            outStatus.pointee = .haveData
            return srcBuffer
        }
        if status == .error { throw convError ?? NSError(domain: "CustomSampleStore", code: 4) }
        guard dstBuffer.frameLength > 0 else {
            throw NSError(domain: "CustomSampleStore", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "conversion produced no frames"])
        }
        return dstBuffer
    }

    /// 저장된 경로에서 재디코딩(앱 시작 시). 실패/없음 → buffer = nil. (Task 3에서 구현)
    func loadPersisted() {}
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter CustomSampleStoreTests`
Expected: PASS (`importDecodesToEngineFormat`, `importBadFileThrows`).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/CustomSampleStore.swift Tests/KeyboardSoundTests/CustomSampleStoreTests.swift
git commit -m "feat: CustomSampleStore 디코딩(SampleProviding) + 파일 복사"
```

---

### Task 3: `CustomSampleStore` — 영속화/복원

**Files:**
- Modify: `Sources/KeyboardSound/Sound/CustomSampleStore.swift` (`loadPersisted` 본문)
- Test: `Tests/KeyboardSoundTests/CustomSampleStoreTests.swift` (테스트 추가)

**Interfaces:**
- Consumes: Task 2의 `CustomSampleStore`
- Produces: `loadPersisted()` 동작(앱 시작 시 복원). Task 7에서 호출.

- [ ] **Step 1: 실패 테스트 추가**

`Tests/KeyboardSoundTests/CustomSampleStoreTests.swift` 끝에 추가:

```swift
@Test func persistsAndReloadsAcrossInstances() throws {
    let dir = tempDir()
    let defs = ephemeralDefaults()
    let src = writeFixtureWAV()

    let store1 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    try store1.importFile(src)

    let store2 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    #expect(store2.buffer == nil)            // load 전엔 비어있음
    store2.loadPersisted()
    #expect(store2.buffer != nil)            // load 후 복원
    #expect(store2.fileName == "fixture.wav")
}

@Test func loadPersistedWithNothingIsNil() {
    let store = CustomSampleStore(format: engineFormat, directory: tempDir(), defaults: ephemeralDefaults())
    store.loadPersisted()
    #expect(store.buffer == nil)
}

@Test func loadPersistedWithMissingFileIsNil() {
    let dir = tempDir()
    let defs = ephemeralDefaults()
    let src = writeFixtureWAV()
    let store1 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    try! store1.importFile(src)
    // 복사본을 지워 "파일 없음" 상황 재현
    try! FileManager.default.removeItem(at: dir)

    let store2 = CustomSampleStore(format: engineFormat, directory: dir, defaults: defs)
    store2.loadPersisted()
    #expect(store2.buffer == nil)            // 크래시 없이 무음
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter CustomSampleStoreTests`
Expected: `persistsAndReloadsAcrossInstances`·`loadPersistedWithMissingFileIsNil` FAIL (`loadPersisted`가 빈 구현).

- [ ] **Step 3: `loadPersisted` 구현**

`CustomSampleStore.swift`의 빈 `loadPersisted()`를 교체:

```swift
    /// 저장된 경로에서 재디코딩(앱 시작 시). 실패/없음 → buffer = nil.
    func loadPersisted() {
        guard let path = defaults.string(forKey: Keys.path),
              FileManager.default.fileExists(atPath: path) else {
            buffer = nil
            return
        }
        do {
            buffer = try Self.decode(url: URL(fileURLWithPath: path), to: format)
            fileName = defaults.string(forKey: Keys.name) ?? URL(fileURLWithPath: path).lastPathComponent
        } catch {
            storeLog.error("loadPersisted decode failed: \(error.localizedDescription, privacy: .public)")
            buffer = nil
        }
    }
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter CustomSampleStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: 커밋**

```bash
git add Sources/KeyboardSound/Sound/CustomSampleStore.swift Tests/KeyboardSoundTests/CustomSampleStoreTests.swift
git commit -m "feat: CustomSampleStore 영속화/복원(loadPersisted)"
```

---

### Task 4: `SamplePlayer` — 모노폰 재생기

**Files:**
- Create: `Sources/KeyboardSound/Sound/SamplePlayer.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `protocol SamplePlaying: AnyObject { func playSample(_ buffer: AVAudioPCMBuffer, volume: Float) }` — Task 6에서 사용.
  - `final class SamplePlayer: SamplePlaying`
    - `init(sampleRate: Double = 44100)`
    - `let format: AVAudioFormat`
    - `@discardableResult func start() -> Bool`
    - `func stop()`
    - `func playSample(_ buffer: AVAudioPCMBuffer, volume: Float)`
  - Task 7에서 사용. (`SoundPlayer`와 동일하게 AVAudioEngine 의존이라 유닛 테스트 없음 — 빌드 검증.)

- [ ] **Step 1: 구현 작성**

Create `Sources/KeyboardSound/Sound/SamplePlayer.swift`:

```swift
import AVFoundation
import os

private let sampleLog = Logger(subsystem: "com.keyboardsound.app", category: "sample")

/// 커스텀 샘플 재생 추상화. 테스트에서 스파이로 대체 가능.
protocol SamplePlaying: AnyObject {
    func playSample(_ buffer: AVAudioPCMBuffer, volume: Float)
}

/// 커스텀 샘플 전용 모노폰 재생기. 합성용 SoundPlayer와 **별도 엔진**을 사용해
/// 기존 합성 오디오 경로에 전혀 영향을 주지 않는다. 메인 스레드 전용.
final class SamplePlayer: SamplePlaying {
    let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    init(sampleRate: Double = 44100) {
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// 엔진을 (필요 시) 시작. 멱등. 실패는 로깅.
    @discardableResult
    func start() -> Bool {
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            node.play()
            return true
        } catch {
            sampleLog.error("SamplePlayer engine start failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func stop() {
        node.stop()
        engine.stop()
    }

    /// 이전 소리를 끊고(예약 버퍼 flush·시점 0) 처음부터 재생(모노폰).
    func playSample(_ buffer: AVAudioPCMBuffer, volume: Float) {
        if !engine.isRunning, !start() {
            sampleLog.error("playSample: engine not running and start() failed")
            return
        }
        node.stop()                                  // flush + sample-time reset
        node.volume = max(0, min(1, volume))
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
git add Sources/KeyboardSound/Sound/SamplePlayer.swift
git commit -m "feat: SamplePlayer 모노폰 재생기(별도 엔진)"
```

---

### Task 5: `Settings.selectCustom()`

**Files:**
- Modify: `Sources/KeyboardSound/Settings/Settings.swift`
- Test: `Tests/KeyboardSoundTests/SettingsCustomTests.swift` (Create)

**Interfaces:**
- Consumes: `Preset.customID` (Task 1)
- Produces: `Settings.selectCustom()` — Task 8·9에서 사용. 효과: `selectedSwitchID = "custom"`.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/KeyboardSoundTests/SettingsCustomTests.swift`:

```swift
import Testing
import Foundation
@testable import KeyboardSound

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sc-\(UUID().uuidString)")!
}

@Test func selectCustomSetsCustomID() {
    let s = Settings(defaults: freshDefaults())
    s.selectCustom()
    #expect(s.selectedSwitchID == Preset.customID)
}

@Test func selectCustomPersistsAcrossInstances() {
    let d = freshDefaults()
    let s1 = Settings(defaults: d)
    s1.selectCustom()
    let s2 = Settings(defaults: d)
    #expect(s2.selectedSwitchID == "custom")
}

@Test func selectingSynthAfterCustomStillWorks() {
    let s = Settings(defaults: freshDefaults())
    s.selectCustom()
    s.selectSwitch(.red)                       // 합성 복귀
    #expect(s.selectedSwitchID == "red")
    #expect(abs(s.tone - Preset.red.tone) < 0.0001)
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter SettingsCustomTests`
Expected: 컴파일 실패 — `selectCustom` 없음.

- [ ] **Step 3: 최소 구현**

`Settings.swift`의 `selectSwitch(_:)` 메서드 바로 아래에 추가:

```swift
    /// 스위치 선택: id 설정(→ didSet이 그 스위치 값 로드).
    func selectSwitch(_ preset: Preset) {
        selectedSwitchID = preset.id
    }

    /// 커스텀 샘플 프리셋 선택. (톤/샤프 등은 커스텀 모드에서 미사용.)
    func selectCustom() {
        selectedSwitchID = Preset.customID
    }
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter SettingsCustomTests`
Expected: PASS (3 tests).

- [ ] **Step 5: 회귀 확인 + 커밋**

```bash
swift test --filter SettingsTests
git add Sources/KeyboardSound/Settings/Settings.swift Tests/KeyboardSoundTests/SettingsCustomTests.swift
git commit -m "feat: Settings.selectCustom() 추가"
```
Expected: 기존 `SettingsTests` 8개 그대로 PASS.

---

### Task 6: `KeySoundController` 커스텀 분기

**Files:**
- Modify: `Sources/KeyboardSound/Coordinator/KeySoundController.swift`
- Test: `Tests/KeyboardSoundTests/KeySoundControllerCustomTests.swift` (Create)

**Interfaces:**
- Consumes: `SampleProviding`(Task 2), `SamplePlaying`(Task 4), `Preset.customID`(Task 1).
- Produces: 새 init 시그니처
  `init(settings:bank:player:sampleStore: SampleProviding? = nil, samplePlayer: SamplePlaying? = nil)`
  — Task 7에서 사용. 기존 호출부는 기본값 nil로 그대로 컴파일.

- [ ] **Step 1: 실패 테스트 작성**

Create `Tests/KeyboardSoundTests/KeySoundControllerCustomTests.swift`:

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter KeySoundControllerCustomTests`
Expected: 컴파일 실패 — init에 `sampleStore`/`samplePlayer` 파라미터 없음.

- [ ] **Step 3: 구현 — init 확장 + 분기**

`Sources/KeyboardSound/Coordinator/KeySoundController.swift` 전체를 교체:

```swift
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
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter KeySoundControllerCustomTests`
Expected: PASS (3 tests).

- [ ] **Step 5: 회귀 확인 + 커밋**

```bash
swift test --filter KeySoundControllerTests
git add Sources/KeyboardSound/Coordinator/KeySoundController.swift Tests/KeyboardSoundTests/KeySoundControllerCustomTests.swift
git commit -m "feat: KeySoundController 커스텀 샘플 분기(down만, 합성 경로 불변)"
```
Expected: 기존 `KeySoundControllerTests` 3개 그대로 PASS.

---

### Task 7: `AppDelegate` 배선 + 커스텀 시 뱅크 재생성 스킵

**Files:**
- Modify: `Sources/KeyboardSound/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `SamplePlayer`(Task 4), `CustomSampleStore`(Task 2·3), 확장된 `KeySoundController` init(Task 6), `SettingsWindowController`의 확장 init(Task 9에서 추가).
- Produces: 실행 시 store/samplePlayer가 컨트롤러에 주입되고, 커스텀 모드에서 `regenerateBank` 스킵.

> 주의: 이 Task는 `SettingsWindowController(settings:sampleStore:onTest:)` 시그니처(Task 9)를 사용한다. 아래 Step 3에서 해당 호출을 변경하므로, **Task 9를 먼저 끝내거나 두 Task를 함께 빌드**해야 컴파일된다. 권장 순서: Task 9 → Task 7, 또는 7·9를 한 번에 구현 후 빌드.

- [ ] **Step 1: store/samplePlayer 프로퍼티 + 생성**

`AppDelegate.swift` 상단 프로퍼티 영역에서 `private let player = SoundPlayer()` 아래에 추가:

```swift
    private let player = SoundPlayer()
    private let samplePlayer = SamplePlayer()
    private let monitor = KeyEventMonitor()

    private var bank: ClickSoundBank!
    private var sampleStore: CustomSampleStore!
```

- [ ] **Step 2: 컨트롤러 주입 + 영속 샘플 로드**

`applicationDidFinishLaunching` 안에서 `bank = ClickSoundBank(...)` 블록 직후, `controller = ...` 줄을 다음으로 교체:

```swift
        bank = ClickSoundBank(format: player.format,
                              tone: settings.tone,
                              sharpness: settings.sharpness,
                              weight: settings.weight,
                              ring: settings.ring,
                              preset: settings.currentSwitch)

        sampleStore = CustomSampleStore(format: samplePlayer.format)
        sampleStore.loadPersisted()

        controller = KeySoundController(settings: settings, bank: bank, player: player,
                                        sampleStore: sampleStore, samplePlayer: samplePlayer)
        monitor.onEvent = { [weak self] event in self?.controller.handle(event) }
```

- [ ] **Step 3: 설정 창에 store 전달**

같은 메서드의 `settingsWindow = SettingsWindowController(settings: settings) { ... }` 호출을 다음으로 교체:

```swift
        settingsWindow = SettingsWindowController(settings: settings, sampleStore: sampleStore) { [weak self] in
            self?.playTestSound()
        }
```

- [ ] **Step 4: 커스텀 시 뱅크 재생성 스킵**

`regenerateBank()` 메서드를 다음으로 교체:

```swift
    private func regenerateBank() {
        // 커스텀 모드에선 합성 뱅크를 쓰지 않으므로 재생성 불필요.
        guard settings.selectedSwitchID != Preset.customID else { return }
        bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, weight: settings.weight, ring: settings.ring, preset: settings.currentSwitch)
    }
```

- [ ] **Step 5: 빌드 확인**

Run: `swift build`
Expected: 성공 (Task 9의 `SettingsWindowController` 변경이 적용된 상태에서).

- [ ] **Step 6: 커밋**

```bash
git add Sources/KeyboardSound/App/AppDelegate.swift
git commit -m "feat: AppDelegate에 CustomSampleStore/SamplePlayer 배선 + 커스텀 시 뱅크 재생성 스킵"
```

---

### Task 8: `StatusMenuController` 커스텀 메뉴 항목

**Files:**
- Modify: `Sources/KeyboardSound/UI/StatusMenuController.swift`

**Interfaces:**
- Consumes: `Settings.selectCustom()`(Task 5), `Preset.customID`(Task 1).
- Produces: 메뉴바 프리셋 서브메뉴에 "커스텀 샘플" 항목.

- [ ] **Step 1: 서브메뉴에 커스텀 항목 추가**

`rebuild()`의 프리셋 서브메뉴 구성 부분에서, `for preset in Preset.all { ... }` 루프 **직후**(서브메뉴에 `presetParent`를 붙이기 전)에 추가:

```swift
        let presetMenu = NSMenu()
        for preset in Preset.all {
            let item = NSMenuItem(title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = (settings.selectedSwitchID == preset.id) ? .on : .off
            presetMenu.addItem(item)
        }
        presetMenu.addItem(.separator())
        let customItem = NSMenuItem(title: "커스텀 샘플", action: #selector(selectCustom), keyEquivalent: "")
        customItem.target = self
        customItem.state = (settings.selectedSwitchID == Preset.customID) ? .on : .off
        presetMenu.addItem(customItem)
```

- [ ] **Step 2: 액션 추가**

`@objc private func selectPreset(_ sender:)` 아래에 추가:

```swift
    @objc private func selectCustom() {
        settings.selectCustom()
        rebuild()
    }
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build`
Expected: 성공.

- [ ] **Step 4: 커밋**

```bash
git add Sources/KeyboardSound/UI/StatusMenuController.swift
git commit -m "feat: 메뉴바 프리셋에 '커스텀 샘플' 항목 추가"
```

---

### Task 9: `SettingsView` 커스텀 UI + 파일 선택, `SettingsWindowController` 배선

**Files:**
- Modify: `Sources/KeyboardSound/UI/SettingsView.swift`
- Modify: `Sources/KeyboardSound/UI/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `CustomSampleStore`(Task 2·3, `@ObservedObject`), `Settings.selectCustom()`(Task 5), `Preset.customID`(Task 1).
- Produces: `SettingsWindowController.init(settings:sampleStore:onTest:)` — Task 7에서 사용.

- [ ] **Step 1: `SettingsView` 교체 (커스텀 분기 + NSOpenPanel)**

`Sources/KeyboardSound/UI/SettingsView.swift` 전체를 교체:

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var sampleStore: CustomSampleStore
    let onTest: () -> Void

    init(settings: Settings, sampleStore: CustomSampleStore, onTest: @escaping () -> Void) {
        self.settings = settings
        self.sampleStore = sampleStore
        self.onTest = onTest
    }

    private var isCustom: Bool { settings.selectedSwitchID == Preset.customID }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyboardSound")
                .font(.headline)

            Picker("스위치", selection: Binding(
                get: { settings.selectedSwitchID },
                set: { id in
                    if id == Preset.customID {
                        settings.selectCustom()
                    } else if let preset = Preset.with(id: id) {
                        settings.selectSwitch(preset)
                    }
                }
            )) {
                ForEach(Preset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                Text("커스텀").tag(Preset.customID)
            }
            .pickerStyle(.segmented)

            if isCustom {
                customSection
            } else {
                synthSection
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("파일 선택…", action: pickFile)
                Text(sampleStore.fileName ?? "선택된 파일 없음")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            Button("테스트 소리", action: onTest)
        }
    }

    private var synthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            slider("볼륨", value: Binding(get: { settings.volume }, set: { settings.volume = $0 }))
            slider("톤",   value: Binding(get: { settings.tone }, set: { settings.tone = $0 }))
            slider("샤프함", value: Binding(get: { settings.sharpness }, set: { settings.sharpness = $0 }))
            slider("무게",  value: Binding(get: { settings.weight }, set: { settings.weight = $0 }))
            slider("울림",  value: Binding(get: { settings.ring }, set: { settings.ring = $0 }))

            HStack {
                Button("테스트 소리", action: onTest)
                Button("값 초기화") { settings.resetCurrentSwitch() }
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sampleStore.importFile(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "오디오 파일을 불러올 수 없습니다"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Slider(value: value, in: 0...1)
        }
    }
}
```

- [ ] **Step 2: `SettingsWindowController` 교체 (store 전달)**

`Sources/KeyboardSound/UI/SettingsWindowController.swift` 전체를 교체:

```swift
import AppKit
import SwiftUI

/// SettingsView를 NSWindow에 호스팅한다.
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let sampleStore: CustomSampleStore
    private let onTest: () -> Void

    init(settings: Settings, sampleStore: CustomSampleStore, onTest: @escaping () -> Void) {
        self.settings = settings
        self.sampleStore = sampleStore
        self.onTest = onTest
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, sampleStore: sampleStore, onTest: onTest)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "KeyboardSound 설정"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
            window?.center()
        }
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: 빌드 확인 (Task 7과 함께)**

Run: `swift build`
Expected: 성공. (Task 7의 AppDelegate 호출이 새 시그니처와 일치.)

- [ ] **Step 4: 커밋**

```bash
git add Sources/KeyboardSound/UI/SettingsView.swift Sources/KeyboardSound/UI/SettingsWindowController.swift
git commit -m "feat: 설정창 커스텀 샘플 UI(파일 선택/볼륨) + store 배선"
```

---

### Task 10: 전체 검증 + README 보강

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 전체 기능.
- Produces: 통과하는 테스트 스위트 + 사용자 문서.

- [ ] **Step 1: 전체 테스트**

Run: `swift test`
Expected: 전부 PASS — 기존 8개 파일 테스트 + 신규(CustomPreset 2, CustomSampleStore 5, SettingsCustom 3, KeySoundControllerCustom 3).

- [ ] **Step 2: 전체 빌드**

Run: `swift build`
Expected: 성공, 경고 없음(또는 기존 수준).

- [ ] **Step 3: 수동 동작 확인 (앱 실행)**

Run: `./scripts/build-app.sh && open KeyboardSound.app`
체크리스트:
- 메뉴바 → 프리셋 → "커스텀 샘플" 선택 가능.
- 사운드 설정 → "커스텀" 세그먼트 → "파일 선택…"으로 오디오 파일 지정 → 파일명 표시.
- 키 입력 시 그 소리가 down에서 재생, 빠르게 치면 이전 소리가 끊기고 재시작(모노폰).
- 합성 프리셋(청축 등)으로 되돌리면 기존 합성음이 **그대로** 동작(회귀 없음).
- 앱 재시작 후에도 커스텀 파일이 유지됨.

- [ ] **Step 4: README 보강**

`README.md`의 사운드/사용 안내에 커스텀 샘플 한 단락 추가. 예: "사운드" 섹션 앞에 추가:

```markdown
## 커스텀 샘플

메뉴바 → 프리셋 → **커스텀 샘플**을 고르고, "사운드 설정 → 커스텀 → 파일 선택…"에서
오디오 파일(wav/aiff/m4a/mp3 등)을 지정하면 키를 누를 때마다 그 소리가 재생됩니다.
(누를 때만 재생되며, 빠르게 입력하면 이전 소리를 끊고 처음부터 다시 재생합니다.)
선택한 파일은 앱 폴더로 복사되어 재시작 후에도 유지됩니다.
```

- [ ] **Step 5: 커밋**

```bash
git add README.md
git commit -m "docs: README에 커스텀 샘플 사용법 추가"
```

---

## Self-Review (작성자 점검 완료)

- **Spec coverage:** 소스=파일 선택(Task 9), 새 프리셋(Task 1·8·9), down만(Task 6), 모노폰(Task 4·6), 파일 복사 영속화(Task 2·3·7), 커스텀 UI=볼륨만(Task 9), 합성 무영향(전 Task additive + 회귀 테스트 Step). 누락 없음.
- **Placeholder scan:** 모든 코드 스텝에 실제 코드 포함. TBD/TODO 없음.
- **Type consistency:** `Preset.customID`, `SampleProviding.buffer`, `SamplePlaying.playSample(_:volume:)`, `CustomSampleStore.importFile/loadPersisted/fileName/buffer`, `KeySoundController.init(...sampleStore:samplePlayer:)`, `SettingsWindowController.init(settings:sampleStore:onTest:)`, `SettingsView.init(settings:sampleStore:onTest:)` — Task 간 시그니처 일치.
- **순서 주의:** Task 7과 9는 `SettingsWindowController`/`SettingsView` 시그니처를 공유하므로 9 → 7 순서(또는 함께 빌드)로 진행. 그 외 Task는 1→2→3→4→5→6 순.
```
