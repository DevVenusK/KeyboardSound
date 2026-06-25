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
