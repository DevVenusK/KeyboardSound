# KeyboardSound

맥에서 키 입력마다 합성된 기계식 키보드 타건음을 내는 메뉴바 앱. 청축/갈축/적축/토프레 스위치를 절차적으로 재현합니다.

## 설치 (Homebrew)

```bash
brew tap DevVenusK/keyboardsound
brew trust devvenusk/keyboardsound   # Homebrew 6.0+ 서드파티 탭 신뢰
brew install --cask keyboardsound
```

설치 후 **시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링**에서 KeyboardSound를 허용하세요. 이 빌드는 공증되지 않아 첫 실행 시 Gatekeeper 경고가 뜰 수 있습니다 — Finder에서 앱 우클릭 → 열기, 또는 `xattr -dr com.apple.quarantine /Applications/KeyboardSound.app`.

## 빌드

```bash
./scripts/build-app.sh
```

스크립트는 저장소 루트에서 실행하세요.

## 실행

```bash
open KeyboardSound.app
```

첫 실행 시 **시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링**에서 KeyboardSound를 허용해야 키 입력이 감지됩니다. (전역 키 이벤트를 듣는 CGEventTap은 입력 모니터링 권한이 필요합니다.)

메뉴바의 키보드 아이콘에서 켜기/끄기, 스위치(청축·갈축·적축·토프레), "사운드 설정…"을 조절할 수 있습니다. 설정 창에서는 **볼륨·톤·샤프함·무게·울림** 슬라이더와 **값 초기화** 버튼을 제공하며, 조절값은 스위치별로 따로 기억됩니다.

## 개발

```bash
swift build      # 빌드
swift test       # 단위 테스트
```

## 사운드

모든 소리는 코드로 합성됩니다(녹음 샘플 미사용 → 저작권 부담 없이 자유 배포 가능). 합성 모델은 접촉음 합성 문헌에 기반해, 노이즈 버스트 여기(접촉력)를 비배음 공진기 뱅크에 통과시키고 광대역 트랜지언트·미세 beating을 더한 뒤 피크 정규화합니다.

## 배포

앱은 **Developer ID Application** 인증서로 서명됩니다(`scripts/build-app.sh`가 자동 선택). 다른 맥에 Gatekeeper 경고 없이 배포하려면 **공증(notarization)**이 추가로 필요합니다.
