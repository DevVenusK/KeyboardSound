# 기계식 스위치 타건음 재현 (청축/갈축/적축/토프레) — 설계

작성일: 2026-06-26

## 1. 목표

현재 프리셋(clicky / tactile / linear / thock)을 **실제 기계식 키보드 스위치 타건음**
재현으로 교체한다: **청축(blue) · 갈축(brown) · 적축(red) · 토프레(topre)**.
각 스위치 아래에 **톤 + 샤프함** 슬라이더를 두어, 선택한 스위치의 캐릭터를 유지한 채
미세 조정할 수 있게 하고, **조정값은 스위치별로 기억**한다.

### 비목표
- 실제 녹음(샘플) 기반 재생 — 완전 절차적 합성을 유지한다(음원/라이선스/용량 부담 회피).
- "진짜 녹음" 수준의 완벽 재현 — 목표는 "그럴듯한 근사".
- 토프레 스프링 공명 레이어 — 초기 범위에서 제외(필요 시 후속).

## 2. 접근 방식

확정된 방향: **절차적 합성 확장** (샘플/하이브리드 아님). 기존 `ClickSynth`(순수 함수)
구조를 유지하며 스위치별 모델링을 코드로 추가한다.

## 3. 합성 모델 변경

### 3.1 신규 파라미터
`SoundParameters`에 **`clickAmount: Double` (0…1)** 한 개만 추가한다.

- 청축의 "딸깍(click jacket)"을 모델링.
- `ClickSynth.render`에 **클릭 트랜지언트 레이어**를 추가: 본체음 위에 아주 짧은
  (~3–5ms) 고주파(~5kHz 중심) 밴드패스 노이즈 버스트를 얹고, 세기를 `clickAmount`로 제어.
- 클릭 레이어는 본체와 별도의 매우 빠른 감쇠를 가진다(어택 직후 수 ms 내 소멸).
- `clickAmount == 0`이면 클릭 레이어는 출력에 전혀 기여하지 않는다(기존 동작과 동일).

### 3.2 기존 파라미터로 표현하는 차별화
- 밝기/어둡기 = `toneFrequency`
- 샤프함/노이즈량 = `sharpness`
- 묵직함/여운 = `decayTime` + `bodyMix`

토프레의 "통" 깊이는 *낮은 tone + 긴 decay + 높은 bodyMix*로 근사한다. 귀로 들어
부족하면 후속에서 공명 레이어를 검토한다(현재 범위 외).

### 3.3 순수성/테스트
`ClickSynth.render`는 순수 함수를 유지한다(동일 파라미터·시드 → 동일 출력). 출력은
기존처럼 [-1, 1]로 소프트 클램프된다.

## 4. 스위치 프리셋

`Preset`에 `clickAmount` 필드를 추가하고, 기존 4개 정적 프리셋을 다음으로 교체한다.
(초기값 — 귀로 미세조정 전제)

| 스위치 | id | name | tone | sharpness | decayTime | bodyMix | humanization | clickAmount |
|---|---|---|---|---|---|---|---|---|
| 청축 | `blue` | 청축 | 0.80 | 0.85 | 0.045 | 0.25 | 0.15 | 0.80 |
| 갈축 | `brown` | 갈축 | 0.55 | 0.55 | 0.060 | 0.45 | 0.20 | 0.00 |
| 적축 | `red` | 적축 | 0.45 | 0.35 | 0.050 | 0.50 | 0.15 | 0.00 |
| 토프레 | `topre` | 토프레 | 0.22 | 0.30 | 0.095 | 0.72 | 0.25 | 0.00 |

- `Preset.all = [.blue, .brown, .red, .topre]`.
- `tone`/`sharpness`는 사용자가 스위치 기준으로 조정하는 슬라이더의 **기본값**.
- `decayTime`/`bodyMix`/`humanization`/`clickAmount`는 스위치 고유 캐릭터(비노출).
- 기본 선택 스위치: **청축(blue)**.

## 5. 데이터 모델 (스위치별 기억)

`Settings` 변경:

- **`custom` 개념 완전 제거.** `presetID` → **`selectedSwitchID`** (항상 4개 중 하나).
- 톤/샤프를 **스위치별로 영속화**: UserDefaults 키 `switch.<id>.tone`,
  `switch.<id>.sharpness`.
- `@Published var tone` / `@Published var sharpness`는 **현재 선택된 스위치의 값**을
  반영한다:
  - `selectedSwitchID` 변경 시: 해당 스위치에 저장된 값을 로드(없으면 그 스위치의
    `Preset` 기본값).
  - `tone`/`sharpness` 변경 시: 현재 `selectedSwitchID` 아래로 저장. (custom 폴백 없음 —
    스위치 정체성 유지.)
- 신규 API:
  - `currentSwitch: Preset` = `Preset.with(id: selectedSwitchID) ?? .blue`
  - `selectSwitch(_ preset: Preset)`: `selectedSwitchID` 설정 후 그 스위치의 톤/샤프 로드.
  - 스위치별 저장값 접근 헬퍼(`storedTone(for:)` / `storedSharpness(for:)` 또는 동등물).
- 제거: `applyPreset`의 custom 동작, `userAdjustedTone`/`userAdjustedSharpness`의
  custom 전환. (톤/샤프 조정은 이제 현재 스위치 아래 저장이 전부.)

### 5.1 루프 방지
`selectedSwitchID` 변경 → 톤/샤프 로드 시, 톤/샤프 didSet이 같은 값을 현재(새) 스위치
id로 다시 저장하는 것은 무해하다. 세 published 변경은 AppDelegate에서 debounce로
합쳐져 한 번의 뱅크 재생성으로 처리된다.

## 6. AppDelegate / 뱅크 재생성

- Combine 파이프라인 형태 유지:
  `settings.$tone.combineLatest(settings.$sharpness, settings.$selectedSwitchID)`
  `.dropFirst().debounce(...).sink { regenerateBank() }`
- `regenerateBank()` → `bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, preset: settings.currentSwitch)`.
- `ClickSoundBank.regenerate(tone:sharpness:preset:)`는 `preset.clickAmount`를
  `SoundParameters`에 채워 합성기로 전달한다(시그니처 변경 없음).

## 7. UI

- **설정 창(`SettingsView`)**: 세그먼트 피커(청축/갈축/적축/토프레) → `selectedSwitchID`
  (`selectSwitch` 호출). 그 아래 볼륨·톤·샤프함 슬라이더. `custom` 태그 분기 삭제.
- **메뉴바(`StatusMenuController`)**: 프리셋 서브메뉴를 4개 스위치로(한글 이름),
  선택 시 `selectSwitch`. 서브메뉴 제목 "스위치".

## 8. 마이그레이션

`Settings.init`에서 기존 사용자 데이터 변환:
- 기존 `presetID` 1:1 매핑 — `clicky→blue`, `tactile→brown`, `linear→red`,
  `thock→topre`. 미지/없음 → `blue`.
- 기존 단일 `tone`/`sharpness`(절대값)가 있으면, 매핑된 스위치의 초기 기억값으로 시드.
- 옛 키(`presetID`, 단일 `tone`/`sharpness`)는 정리(또는 무시).

## 9. 테스트 (Swift Testing, 기존 패턴)

- **ClickSynth**: `clickAmount>0`가 `clickAmount=0` 대비 출력을 변화시키고 고주파
  에너지를 추가한다; 출력은 여전히 [-1,1] bounded; 동일 시드·파라미터 동일 출력.
- **ClickSoundBank**: 4개 스위치 각각 비어있지 않은 버퍼 생성; `clickAmount`가
  합성 경로로 전파됨(청축 vs 적축 버퍼 상이).
- **Settings**: 청축 톤 조정 → 적축 전환(적축 값 노출) → 청축 복귀 시 청축 조정값 복원;
  인스턴스 간 영속; 스위치 선택이 그 스위치 값 로드; 마이그레이션 매핑 동작.
- **Preset**: 4개 스위치 id/이름/`clickAmount` 존재 및 `all` 구성.

## 10. 영향 받는 파일

- `Sound/SoundParameters.swift` — `clickAmount` 추가
- `Sound/ClickSynth.swift` — 클릭 트랜지언트 레이어
- `Sound/Preset.swift` — 4개 스위치 프리셋 + `clickAmount`
- `Sound/ClickSoundBank.swift` — `clickAmount` 전파
- `Settings/Settings.swift` — 스위치별 기억 모델 + 마이그레이션
- `App/AppDelegate.swift` — Combine 키 `selectedSwitchID`, `currentSwitch` 사용
- `UI/SettingsView.swift` — 피커/슬라이더, custom 제거
- `UI/StatusMenuController.swift` — 스위치 서브메뉴
- `Tests/*` — 위 테스트
