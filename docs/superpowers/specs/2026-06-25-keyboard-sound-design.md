# KeyboardSound — 기계식 키보드 사운드 macOS 앱 (설계 / Spec)

- 작성일: 2026-06-25
- 상태: 설계 확정, 사용자 리뷰 대기
- 대상 플랫폼: macOS 13.0+ (Ventura 이상)

## 1. 목표 (Goal)

macOS에서 **물리 키를 누를 때마다 기계식 키보드 클릭음을 시스템 전역으로 재생**하는 메뉴바 앱.
사운드는 **코드로 실시간 합성**(녹음 샘플 미사용)하여 저작권 부담이 없고 자유롭게 배포 가능하다.
사용자는 프리셋과 슬라이더로 소리를 자기 취향에 맞게 조절할 수 있다.

## 2. 비목표 (Non-goals, v1 제외)

- 녹음/샘플 기반 사운드 (합성만)
- 로그인 시 자동 실행 (v2)
- Developer ID 서명 / 공증(notarization) — 정식 배포 시점의 별도 단계 (4.7 참고)
- 앱별 on/off, 단축키로 토글
- 마우스 클릭음 (키보드 전용)

## 3. 핵심 결정 (Decisions)

| 항목 | 결정 | 이유 |
|---|---|---|
| 앱 형태 | 메뉴바 전용 앱 (`LSUIElement`, Dock 아이콘 없음) | 켜두고 토글하는 도구의 표준 macOS 형태 |
| 키 감지 | `CGEventTap` (듣기 전용, `keyDown`/`keyUp`/`flagsChanged`) | 전역 감지 + 자동반복 플래그 제공 + 타이핑 비간섭 |
| 자동반복 | 무시 (꾹 누름 반복 입력은 소리 안 냄) | 기계총 소리 방지, 자연스러움 |
| 사운드 | 절차적 합성 (AVAudioEngine, PCM 버퍼 사전 렌더) | 저작권 안전·배포 가능, 외부 의존 0, 저지연 |
| 사운드 디테일 | 키별 피치 변화 + 다운/업 클릭 + 특수키 thock | "리얼함" 목표 충족 |
| 조절 | 프리셋(Clicky/Tactile/Linear/Thock) + 슬라이더 3개(볼륨·톤·샤프함), 설정 창 | 판단 피로 최소화 + 충분한 튜닝 |
| 권한 | Accessibility(손쉬운 사용) — 첫 실행 시 시스템 설정 안내 | 전역 키 감지에 필수 |
| 패키징 | SPM 빌드 → `.app` 번들 조립, ad-hoc 서명 (개인용) | Xcode GUI 불필요, CLI 재현 가능 |

## 4. 아키텍처

### 4.1 컴포넌트 개요

각 단위는 한 가지 책임만 갖고 명확한 인터페이스로 통신한다.

| 컴포넌트 | 책임 | 의존 |
|---|---|---|
| `KeyboardSoundApp` | 앱 진입점, 전 컴포넌트 연결, 생명주기 | AppKit |
| `KeyEventMonitor` | CGEventTap 래핑, 자동반복 필터링, `KeyEvent` 콜백, 권한/탭 생명주기 | CoreGraphics, ApplicationServices |
| `ClickSoundBank` | 합성 PCM 버퍼 뱅크 사전 생성, keyCode→그룹/변형 매핑 | AVFoundation |
| `SoundPlayer` | AVAudioEngine + 플레이어 노드 풀, `play(buffer, volume)` | AVFoundation |
| `KeySoundController` | 조율: 키 이벤트→버퍼 선택→재생, 설정 변경 반영 | 위 3개 + Settings |
| `Settings` | UserDefaults 영속화 + `ObservableObject` 발행 | Foundation, Combine |
| `Preset` | 프리셋 정의 + 합성 파라미터 묶음 | Foundation |
| `StatusMenuController` | 메뉴바 아이콘/메뉴, 권한 상태 표시, 설정 창 띄우기 | AppKit |
| `SettingsView` | SwiftUI 설정 창 (프리셋 + 슬라이더 3개) | SwiftUI |

### 4.2 데이터 흐름

```
키 누름
  → CGEventTap 콜백 (KeyEventMonitor: 자동반복/모디파이어 전이 판정)
  → KeyEvent(keyCode, phase: .down/.up) 콜백
  → KeySoundController (enabled 확인)
  → ClickSoundBank.buffer(forKeyCode:phase:)  // 그룹+변형 선택
  → SoundPlayer.play(buffer, volume: settings.volume)
  → 스피커
```

설정 변경 흐름:
- 볼륨 변경 → 재생 시점에 즉시 반영 (뱅크 재생성 불필요)
- 톤/샤프함/프리셋 변경 → `ClickSoundBank` 재생성 (파라미터가 합성에 영향)
- enabled 변경 → `KeyEventMonitor`/`SoundPlayer` 시작·정지

### 4.3 KeyEventMonitor

- `CGEvent.tapCreate`로 `cgSessionEventTap`, 옵션 `kCGEventTapOptionListenOnly`(이벤트 수정 안 함), 마스크 = `keyDown | keyUp | flagsChanged`.
- 콜백 처리:
  - `keyDown`: `CGEventGetIntegerValueField(event, .keyboardEventAutorepeat)` == 1 이면 **무시**. 아니면 keyCode 추출(`.keyboardEventKeycode`) 후 `.down` 발행.
  - `keyUp`: keyCode 추출 후 `.up` 발행.
  - `flagsChanged`(모디파이어 Shift/Ctrl/Opt/Cmd/Caps): 직전 플래그와 비교해 해당 모디파이어 비트가 0→1 이면 `.down`(thock 그룹), 1→0 이면 `.up`. 모디파이어 직전 상태를 내부에 보관.
  - `kCGEventTapDisabledByTimeout` / `kCGEventTapDisabledByUserInput`: 시스템이 탭을 비활성화한 경우 → `CGEvent.tapEnable(tap:enable:true)`로 재활성화.
- 런루프: `CFRunLoopAddSource`로 메인 런루프에 소스 추가.
- 권한: `tapCreate`가 `nil` 반환(미허가) → 상태 `.permissionDenied`. 정상 → `.active`.
- 인터페이스:
  - `var onEvent: ((KeyEvent) -> Void)?`
  - `func start() -> StartResult` (`.active` | `.permissionDenied`)
  - `func stop()`
  - `var status: MonitorStatus`
- **순수 판정 함수 분리(테스트 대상)**: `func shouldEmit(eventType:, autorepeat:, prevFlags:, newFlags:) -> KeyEvent?` — CGEventTap 없이 단위 테스트.

### 4.4 ClickSoundBank (합성)

키 그룹:
- `normal`: 일반 문자/숫자/기호 키 → 높은 피치 클릭
- `wide`(thock): Space, Return, Delete(Backspace), Tab, 화살표, 모디파이어 → 낮고 묵직한 thock

`keyCode → group` 매핑 테이블을 보유. (Space=49, Return=36, Delete=51, Tab=48, 화살표 123–126, 모디파이어는 flagsChanged 경로에서 wide 지정)

사전 렌더:
- 그룹별로 **down 변형 N개(기본 6)** + **up 변형 N개**를 init 시 생성하여 `[AVAudioPCMBuffer]`로 보관.
- `buffer(forKeyCode:phase:)`:
  1. keyCode → group
  2. keyCode 기반 결정적 피치 오프셋(같은 키는 비슷한 톤)
  3. 변형 인덱스 = keyCode 해시 + 호출 카운터 기반(휴머나이즈), 결정적이되 변화 있음
  4. 해당 group/phase 변형 버퍼 반환

합성 알고리즘 (down 클릭):
- 트랜지언트 = 화이트 노이즈 버스트를 `toneFreq` 중심 밴드패스 필터에 통과 + 빠른 지수 어택-디케이 엔벨로프(어택 ~1ms, 디케이 = `decayTime`).
- 바디 = 낮은 공명 주파수의 감쇠 사인.
- (옵션) 고역 "스프링" 파셜을 낮은 진폭으로 가산.
- 길이: 일반 30–60ms, thock 60–100ms.
- up 클릭 = down의 더 짧고(약 60%) 낮은 진폭(약 50%) 릴리스 버전.

합성 파라미터 ↔ 슬라이더 매핑(정규화 0–1):
- **톤(tone)**: `toneFreq` 및 바디 주파수 스케일. 낮음=thock, 높음=click. (예: 600Hz–4kHz 로그 매핑)
- **샤프함(sharpness)**: 노이즈:바디 비율 + 어택 가파름 + 고역량. 낮음=부드러움, 높음=또렷함.
- **여운/변화량**: 프리셋 값에 포함(슬라이더 비노출, v1).
- **볼륨**: 합성 아닌 재생 게인 → 뱅크 재생성 불필요.

특성:
- 순수 DSP, I/O 없음 → 단위 테스트 가능.
- 출력은 NaN/무음이 아님을 보장(엔벨로프·게인 클램프).

### 4.5 SoundPlayer

- `AVAudioEngine` + `AVAudioMixerNode` + **AVAudioPlayerNode 풀(기본 8개)** 라운드로빈 → 빠른 연타 폴리포니(겹침) 처리.
- `play(buffer, volume)`: 다음 노드 선택 → `node.volume = volume` → `scheduleBuffer(buffer, at: nil)` → 필요 시 `node.play()`.
- 엔진은 enabled 동안 계속 구동(저지연). `start()` 실패 시 throw 처리.
- 인터페이스: `func start() throws`, `func stop()`, `func play(_ buffer: AVAudioPCMBuffer, volume: Float)`.

### 4.6 Settings / Preset

`Settings` (`ObservableObject`, UserDefaults 백킹):
- `enabled: Bool` (기본 true)
- `presetID: String` (기본 "clicky")
- `volume: Double` 0–1 (기본 0.7)
- `tone: Double` 0–1
- `sharpness: Double` 0–1
- 슬라이더를 수동 조정하면 `presetID = "custom"`으로 전환.

`Preset` (불변 정의):
- 필드: `id`, `name`, `toneDefault`, `sharpnessDefault`, `decayTime`, `bodyMix`, `humanization`
- 내장 4종: `Clicky`(높은 톤·또렷), `Tactile`(중간), `Linear`(부드러움), `Thock`(낮은 톤·묵직).
- 프리셋 선택 시 `tone`/`sharpness`를 프리셋 기본값으로 세팅, 내부 `decayTime`/`bodyMix`/`humanization`도 적용.

### 4.7 패키징 / 빌드

- SPM executable 타깃 (의존: AppKit, AVFoundation, SwiftUI, Combine — 시스템 프레임워크).
- 빌드 스크립트(`scripts/build-app.sh`)가 `KeyboardSound.app` 번들 조립:
  - `Contents/MacOS/KeyboardSound` (swift build 산출물)
  - `Contents/Info.plist`: `LSUIElement=true`, `CFBundleIdentifier`(예 `com.keyboardsound.app`, 재빌드 간 고정), `CFBundleName`, `CFBundleShortVersionString`, `LSMinimumSystemVersion=13.0`, `NSPrincipalClass=NSApplication`.
  - `codesign -s - --force --deep KeyboardSound.app` (ad-hoc).
- 실행/권한 부여 안내를 README에 문서화.
- **정식 배포(추후, v1 외)**: Developer ID 서명 + 공증 + 스테이플. (재빌드 시 ad-hoc cdhash 변경으로 권한 재승인 필요할 수 있음 — 개인용 한정 감수)

## 5. 권한 UX

- 첫 실행: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` → "시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용" 안내 다이얼로그.
- 미허가 동안 메뉴바에 `⚠️ 손쉬운 사용 권한 필요 — 설정 열기` 표시.
- 권한 재확인: 메뉴 열릴 때(`menuWillOpen`) + 미허가 동안 2초 주기 폴링 → 부여되면 **재시작 없이** 자동 활성화.

## 6. 메뉴바 UI

`NSStatusItem` (SF Symbol `keyboard`). 메뉴 항목:
- ✓ 켜기/끄기 토글
- 프리셋 빠른 선택 (Clicky / Tactile / Linear / Thock)
- 사운드 설정… (SettingsView 창 열기)
- (미허가 시만) ⚠️ 손쉬운 사용 권한 필요 — 설정 열기
- 종료

설정 창(`SettingsView`, SwiftUI, `NSHostingController`):
- 프리셋 선택(세그먼트/리스트, 현재 "Custom" 표시 포함)
- 슬라이더 3개: 볼륨 / 톤 / 샤프함
- "테스트 소리" 버튼 (창 포커스 중 미리듣기용)

## 7. 에러 처리

| 상황 | 처리 |
|---|---|
| `tapCreate` nil (미허가) | `.permissionDenied` 상태, 크래시 없음, 메뉴에 안내 |
| 시스템이 탭 비활성화 | 해당 이벤트 감지 → `tapEnable`로 재활성화 |
| `AVAudioEngine.start()` throw | 로그 + enabled false + 메뉴에 오류 표시 |
| 합성 버퍼 이상치 | 엔벨로프/게인 클램프로 NaN·무음 방지 |

## 8. 테스트

### 단위 테스트 (Swift Testing)
- `ClickSoundBankTests`:
  - 버퍼 비어있지 않음 / 길이 예상 범위(ms) / RMS > 0 (무음 아님)
  - keyCode→그룹 매핑: Space/Return/Delete/Tab/화살표 → `wide`, 문자키 → `normal`
  - 변형 결정성: 같은 (keyCode, phase, seed) → 동일 버퍼
- `SettingsTests`:
  - UserDefaults 영속화 왕복
  - 프리셋 적용 시 tone/sharpness 기대값 세팅
  - 슬라이더 수동 조정 시 presetID → "custom"
- `KeyEventFilterTests`:
  - `shouldEmit`: keyDown+autorepeat=1 → nil(무시); =0 → `.down`; keyUp → `.up`; 모디파이어 0→1 → `.down`, 1→0 → `.up`

### 수동 검증 (시스템 의존: CGEventTap, 오디오)
- 실행 → 권한 부여 → 타이핑 시 소리
- 토글 off → 무음
- 프리셋/슬라이더 변경 → 소리 변화
- 빠른 연타 → 겹침 재생, 글리치 없음
- 키 꾹 누름 → 단발 소리(연사 없음)
- 모디파이어 키 → thock 소리

## 9. 빌드/실행 산출물

- `Package.swift` (executable 타깃 + 테스트 타깃)
- `Sources/KeyboardSound/` 소스
- `Tests/KeyboardSoundTests/` 테스트
- `scripts/build-app.sh` (.app 조립 + ad-hoc 서명)
- `README.md` (빌드/실행/권한 부여 안내)
