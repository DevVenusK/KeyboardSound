import AppKit
import SwiftUI

/// SettingsView를 NSWindow에 호스팅한다.
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let onTest: () -> Void

    init(settings: Settings, onTest: @escaping () -> Void) {
        self.settings = settings
        self.onTest = onTest
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, onTest: onTest)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "KeyboardSound 설정"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
            window?.center()
        }
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
