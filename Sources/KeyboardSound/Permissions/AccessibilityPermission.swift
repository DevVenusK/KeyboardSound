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
