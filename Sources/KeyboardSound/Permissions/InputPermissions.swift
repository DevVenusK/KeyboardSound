import AppKit
import IOKit.hid

/// 전역 키 이벤트 수신에 필요한 권한 확인/요청/안내.
///
/// listen-only `CGEventTap`이 keyDown/keyUp 키스트로크를 받으려면 **입력 모니터링
/// (Input Monitoring, TCC `kTCCServiceListenEvent`)** 권한이 필요하다. 손쉬운 사용
/// (Accessibility)은 이벤트를 주입/수정하는 active 탭에만 필요해 listen-only인 이 앱엔
/// 불필요하므로 다루지 않는다.
///
/// 주의: `CGEvent.tapCreate`는 권한이 없어도 성공(non-nil)할 수 있고, 그 경우 모디파이어
/// (flagsChanged)는 들어오지만 keyDown/keyUp은 막힌다. 따라서 탭 생성 성공만으로
/// "동작 중"이라 판단하면 안 되고, 반드시 `isInputMonitoringGranted`로 확인해야 한다.
enum InputPermissions {
    /// 입력 모니터링이 부여되어 전역 키 입력을 실제로 받을 수 있는가.
    static var isInputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 미결정(unknown) 상태면 시스템 권한 프롬프트를 띄우고 부여 여부를 반환한다.
    /// 이미 거부(denied) 상태면 프롬프트 없이 false를 반환하므로, 그 경우엔
    /// `openSettings()`로 설정 패널을 안내해야 한다.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// 시스템 설정의 "개인정보 보호 및 보안 › 입력 모니터링" 패널을 연다.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
