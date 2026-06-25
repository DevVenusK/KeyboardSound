# KeyboardSound

맥에서 키 입력마다 합성된 기계식 키보드 클릭음을 내는 메뉴바 앱.

## 빌드

```bash
./scripts/build-app.sh
```

## 실행

```bash
open KeyboardSound.app
```

첫 실행 시 **시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용**에서 KeyboardSound를 허용해야 키 입력이 감지됩니다.
메뉴바의 키보드 아이콘에서 켜기/끄기, 프리셋(Clicky/Tactile/Linear/Thock), "사운드 설정…"(볼륨·톤·샤프함)을 조절할 수 있습니다.

## 개발

```bash
swift build      # 빌드
swift test       # 단위 테스트
```

## 사운드

모든 소리는 코드로 합성되며(녹음 샘플 미사용) 저작권 부담 없이 자유롭게 배포할 수 있습니다.

## 정식 배포 (추후)

남에게 배포하려면 ad-hoc 서명 대신 Apple Developer ID 서명 + 공증(notarization)이 필요합니다.
