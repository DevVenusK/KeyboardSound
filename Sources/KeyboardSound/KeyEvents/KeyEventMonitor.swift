import CoreGraphics
import Foundation

/// CGEventTap(듣기 전용)으로 전역 키 이벤트를 받아 필터링 후 onEvent로 발행한다.
final class KeyEventMonitor {
    enum Status {
        case inactive
        case active
        case permissionDenied
    }

    var onEvent: ((KeyEvent) -> Void)?
    private(set) var status: Status = .inactive

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: UInt64 = 0

    @discardableResult
    func start() -> Status {
        guard tap == nil else { return status }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = .permissionDenied
            return status
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = .active
        return status
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
        status = .inactive
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // 시스템이 탭을 끈 경우 재활성화.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let currentFlags = event.flags.rawValue

        let rawType: RawKeyEventType
        var modifierMask: UInt64 = 0
        switch type {
        case .keyDown:
            rawType = .keyDown
        case .keyUp:
            rawType = .keyUp
        case .flagsChanged:
            rawType = .flagsChanged
            modifierMask = KeyEventFilter.modifierMask(forKeyCode: keyCode) ?? 0
        default:
            return
        }

        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let result = KeyEventFilter.decide(
            type: rawType,
            keyCode: keyCode,
            isAutorepeat: isAutorepeat,
            previousFlags: previousFlags,
            currentFlags: currentFlags,
            modifierMask: modifierMask
        )

        if type == .flagsChanged {
            previousFlags = currentFlags
        }
        if let result {
            onEvent?(result)
        }
    }
}
