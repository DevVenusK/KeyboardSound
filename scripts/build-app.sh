#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

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
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 서명 식별자 선택: 안정적 인증서(Developer ID > Apple Development)가 있으면 사용한다.
# 안정 인증서로 서명하면 designated requirement가 빌드마다 동일 → 입력 모니터링 권한
# grant가 리빌드해도 유지된다. 없으면 ad-hoc 폴백(리빌드마다 재승인 필요).
SIGN_IDENTITY="${KBSND_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
fi
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
        | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
fi

if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> 코드 서명 (안정 인증서: ${SIGN_IDENTITY})"
    codesign --force --sign "${SIGN_IDENTITY}" "${APP_DIR}"
else
    echo "==> 코드 서명 (ad-hoc — 안정 인증서 없음; 리빌드 시 권한 재승인 필요)"
    codesign --force --deep --sign - "${APP_DIR}"
fi

echo "==> 완료: ${APP_DIR}"
echo "실행: open ${APP_DIR}  (첫 실행 시 입력 모니터링 권한 부여 필요)"
