# 커스텀 오디오 샘플 타건음 — 설계

작성일: 2026-06-29

## 1. 목표

사용자가 **오디오 파일을 골라서**, 키를 **누를 때마다** 그 소리를 재생할 수 있게 한다.
기존 합성 스위치(청축/갈축/적축/토프레)와 나란히 **새 프리셋 "커스텀 샘플"** 로 추가한다.

### 핵심 제약 — 기존 기능 무영향
이 작업은 **완전 추가형(additive-only)** 이어야 한다. 합성음 4종·슬라이더·영속화·권한
흐름은 코드·동작 모두 그대로 유지하고, 커스텀은 사용자가 **명시적으로 선택할 때만**
동작한다. 기존 8개 테스트 파일은 **수정 없이 그대로 통과**해야 한다(새 테스트는 추가만).

### 비목표
- 마이크 녹음 — 이번 범위 제외(파일 선택만).
- 키 뗌(up)에서의 재생 — down에서만 재생.
- down/up 또는 키별로 서로 다른 파일 — 단일 파일 하나.
- 폴리포니(겹쳐 울림) — 커스텀은 **모노폰**(이전 소리 끊고 처음부터).
- 피치/톤 변형, 머신건 방지 지터 — 커스텀 샘플엔 적용 안 함(볼륨만 적용).

## 2. 접근 방식

확정된 방향: **새 프리셋 + 전용 샘플 컴포넌트(C안)**. 합성 경로(`ClickSynth` /
`ClickSoundBank` / `SoundPlayer`)는 **전혀 손대지 않는다**. 커스텀 관련 디코딩·재생은
신규 컴포넌트(`CustomSampleStore`, `SamplePlayer`)에 격리하고, `KeySoundController`가
선택된 프리셋에 따라 경로를 분기한다.

### 2.1 폐기한 위험 요소 (초안에서 제거)
- ❌ `Preset.custom`을 `Preset.all`에 추가 → `PresetTests`(count==4) 및 `Preset.all`
  순회 코드 전부 파급. **대신** `Preset.customID` 상수만 추가하고 `Preset.all`은 그대로.
- ❌ `SoundPlaying` 프로토콜에 메서드 추가 → `KeySoundControllerTests`의 `SpyPlayer`
  컴파일 깨짐. **대신** 별도 `SamplePlaying` 프로토콜을 신설.

## 3. 신규 컴포넌트

### 3.1 `Sound/CustomSampleStore.swift` (신규)
사용자 파일의 보관·디코딩·영속화를 담당.

- **import**: 파일 URL을 받아 `~/Library/Application Support/KeyboardSound/`로 **복사**
  (원본을 옮기거나 지워도 안전). 복사본 경로를 UserDefaults에 저장.
- **decode**: `AVAudioFile`로 읽어, 엔진 포맷(44.1kHz / 스테레오 / float)으로
  `AVAudioConverter`를 통해 변환한 `AVAudioPCMBuffer`를 메모리에 보관.
- **노출 API**:
  - `var buffer: AVAudioPCMBuffer?` — 디코딩 성공 시 버퍼, 없으면 nil.
  - `var fileName: String?` — 현재 파일 표시명(UI용).
  - `func importFile(_ url: URL) throws` — 복사 + 디코딩 + 경로 저장.
  - `func loadPersisted()` — 저장된 경로에서 재디코딩(앱 시작 시). 파일 없거나 실패 →
    buffer = nil(무음), 에러는 로깅.
- 지원 포맷: macOS가 디코딩 가능한 것(wav/aiff/m4a/mp3/caf 등).
- 영속화 키는 **신규 전용 키**(예: `customSamplePath`). 기존 키와 무관.

### 3.2 `Sound/SamplePlayer.swift` (신규)
커스텀 전용 **모노폰** 재생기. 합성용 `SoundPlayer`와 완전 분리.

- 프로토콜:
  ```swift
  protocol SamplePlaying: AnyObject {
      func playSample(_ buffer: AVAudioPCMBuffer, volume: Float)
  }
  ```
- 구현: **자체 `AVAudioEngine` + 단일 `AVAudioPlayerNode`**.
  - `start()` — 멱등, 엔진 시작(커스텀 진입 시 호출). 실패는 로깅(`SoundPlayer`와 동일 패턴).
  - `stop()` — 노드/엔진 정지.
  - `playSample(_:volume:)` — `node.stop()`(예약 버퍼 비우고 시점 0) → `scheduleBuffer`
    → `node.play()` = "이전 소리 끊고 처음부터". 엔진이 꺼져 있으면 재생 직전 보장 시작
    (`SoundPlayer.play`와 동일한 방어).
  - 메인 스레드 전용(`SoundPlayer`와 동일 계약).

## 4. 기존 파일 변경 — 추가만

### 4.1 `Sound/Preset.swift`
- `static let customID = "custom"` **상수 1줄만 추가**.
- `Preset` struct, `Preset.all`(4개), `with(id:)` **변경 없음**.
  → `with(id: "custom")`는 기존대로 `nil`(테스트 영향 없음).

### 4.2 `Settings/Settings.swift`
- 신규 published 프로퍼티 + 키: 커스텀 파일 경로 보관은 `CustomSampleStore`가 담당하되,
  Settings는 **선택 상태**만 다룬다. `selectedSwitchID`에 `"custom"`을 담을 수 있게
  `func selectCustom()` 추가(`selectedSwitchID = Preset.customID`).
- `selectedSwitchID` 의 기존 didSet(`loadAdjustments`)은 `Preset.with(id:"custom") ?? .blue`
  로 떨어져 blue 기본값을 tone/sharpness에 로드 → **무해**(커스텀 모드에선 미사용).
- 기존 키·마이그레이션·`currentSwitch`(→ custom일 때 `.blue` 폴백) **변경 없음**.

### 4.3 `Coordinator/KeySoundController.swift`
- init에 옵셔널 파라미터 **기본값 nil** 추가:
  ```swift
  init(settings: Settings, bank: ClickSoundBank, player: SoundPlaying,
       sampleStore: CustomSampleStore? = nil, samplePlayer: SamplePlaying? = nil)
  ```
  → 기존 호출부(`KeySoundControllerTests`)는 수정 없이 컴파일.
- `handle`에 분기 추가(합성 분기는 그대로):
  ```swift
  func handle(_ event: KeyEvent) {
      guard settings.enabled else { return }
      if settings.selectedSwitchID == Preset.customID {
          guard event.phase == .down, let buf = sampleStore?.buffer else { return }
          samplePlayer?.playSample(buf, volume: Float(settings.volume))
          return
      }
      let buffer = bank.buffer(forKeyCode: event.keyCode, phase: event.phase)
      player.play(buffer, volume: Float(settings.volume))
  }
  ```
  → 기존 테스트는 전부 `selectedSwitchID == "blue"` 상태라 커스텀 분기 미진입.

### 4.4 `UI/SettingsView.swift`
- 세그먼트 피커에 **"커스텀" 1칸 추가**: `ForEach(Preset.all)` 그대로 두고 그 뒤에
  수동 `Text("커스텀").tag(Preset.customID)`. (`Preset.all` 미변경.)
- 피커 `set` 분기: id가 `customID`면 `settings.selectCustom()`, 아니면 기존
  `selectSwitch`.
- 본문 조건부:
  - 커스텀 선택 시 → **`파일 선택…` 버튼 + 현재 파일명 + 볼륨 슬라이더만** 표시
    (톤/샤프/무게/울림 숨김, "값 초기화" 숨김 또는 비활성). 파일 미선택이면 안내 문구.
  - 합성 선택 시 → **기존 UI 그대로**(볼륨·톤·샤프·무게·울림·테스트·초기화).
- `파일 선택…` → `NSOpenPanel`로 오디오 파일 선택 → `store.importFile(url)`.

### 4.5 `UI/StatusMenuController.swift`
- 프리셋 서브메뉴: 기존 `Preset.all` 루프 **그대로** + 그 아래 "커스텀 샘플" 항목 1개
  추가(선택 시 `settings.selectCustom()`, 체크표시는 `selectedSwitchID == customID`).

### 4.6 `App/AppDelegate.swift`
- `CustomSampleStore`·`SamplePlayer` 생성, `loadPersisted()` 호출, 컨트롤러에 주입.
- `regenerateBank()`는 커스텀일 때 **스킵**(`guard selectedSwitchID != customID`).
  합성 프리셋 배선·debounce 파이프라인은 그대로.
- `setEnabled`/권한 워처는 변경 없음. (`SamplePlayer`는 커스텀 진입 시 start.)

## 5. 동작 흐름

```
keyDown ──> KeySoundController.handle
              │  enabled? ──no──> (무음)
              │  selectedSwitchID == "custom"?
              │     ├─ yes ─> down만 + buffer 있으면 SamplePlayer.playSample (모노폰)
              │     └─ no  ─> ClickSoundBank.buffer ─> SoundPlayer.play (기존, 폴리포니)
```

## 6. 영속성·엣지 케이스

- 앱 재시작: `store.loadPersisted()`로 저장된 경로 재디코딩. 파일 없음/실패 → 무음 +
  설정창 안내. selectedSwitchID가 `"custom"`이면 커스텀 모드 유지.
- 커스텀 선택했지만 파일 미선택 → 무음(크래시 없음, `guard let buf` 통과 안 함).
- 파일 교체: 다시 `importFile` 하면 복사본 덮어쓰기 + 재디코딩.
- 디코딩 실패(손상/미지원): 에러 로깅 + buffer = nil(무음).

## 7. 테스트 (Swift Testing, 추가만)

기존 테스트 파일은 **수정 금지**(그대로 통과 확인). 신규로 추가:

- **CustomSampleStore**: 작은 fixture 오디오 파일 import → buffer 비어있지 않음·엔진 포맷
  일치; 경로 영속화 후 `loadPersisted`로 복원; 없는 경로 → buffer nil(크래시 없음);
  fileName 노출.
- **KeySoundController (커스텀 모드)**: 스파이 `SamplePlaying` 주입,
  `selectedSwitchID = "custom"` 상태에서 — down은 `playSample` 1회, up은 무호출,
  store.buffer == nil이면 무호출, enabled=false면 무호출. (기존 합성 스파이 테스트와 별개.)
- **Preset**: `Preset.customID == "custom"`이고 `Preset.with(id: customID) == nil`,
  `Preset.all.count == 4` 불변.

## 8. 영향 받는 파일

신규:
- `Sound/CustomSampleStore.swift`
- `Sound/SamplePlayer.swift`
- `Tests/KeyboardSoundTests/CustomSampleStoreTests.swift`
- `Tests/KeyboardSoundTests/`(커스텀 컨트롤러 테스트 — 기존 파일에 추가 또는 신규 파일)
- 테스트용 fixture 오디오 파일

변경(추가만, 기존 동작 불변):
- `Sound/Preset.swift` — `customID` 상수
- `Settings/Settings.swift` — `selectCustom()`
- `Coordinator/KeySoundController.swift` — 커스텀 분기 + 옵셔널 주입
- `UI/SettingsView.swift` — 커스텀 피커 칸 + 조건부 UI + NSOpenPanel
- `UI/StatusMenuController.swift` — 커스텀 메뉴 항목
- `App/AppDelegate.swift` — store/samplePlayer 배선 + regen 스킵

손대지 않음(합성 핵심):
- `Sound/ClickSynth.swift`, `Sound/ClickSoundBank.swift`, `Sound/SoundPlayer.swift`,
  `Sound/SoundParameters.swift`, `Sound/Biquad.swift`, `KeyEvents/*`
