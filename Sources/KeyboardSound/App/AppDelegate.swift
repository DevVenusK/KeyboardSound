import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let player = SoundPlayer()
    private let monitor = KeyEventMonitor()

    private var bank: ClickSoundBank!
    private var controller: KeySoundController!
    private var menuController: StatusMenuController!
    private var settingsWindow: SettingsWindowController!

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bank = ClickSoundBank(format: player.format,
                              tone: settings.tone,
                              sharpness: settings.sharpness,
                              preset: settings.currentPreset)
        controller = KeySoundController(settings: settings, bank: bank, player: player)
        monitor.onEvent = { [weak self] event in self?.controller.handle(event) }

        settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
            self?.playTestSound()
        }
        menuController = StatusMenuController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onOpenPermission: { AccessibilityPermission.openSettings() }
        )

        // 톤/샤프함/프리셋 변경 → 뱅크 재생성
        settings.$tone
            .combineLatest(settings.$sharpness, settings.$presetID)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.regenerateBank() }
            .store(in: &cancellables)

        // enabled 변경 → 시작/정지
        settings.$enabled
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.promptIfNeeded()
        }
        setEnabled(settings.enabled)
        startPermissionWatcher()
    }

    private func regenerateBank() {
        bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, preset: settings.currentPreset)
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            try? player.start()
            let status = monitor.start()
            menuController?.setPermissionDenied(status == .permissionDenied)
        } else {
            monitor.stop()
            player.stop()
        }
    }

    private func playTestSound() {
        guard settings.enabled, AccessibilityPermission.isTrusted else { return }
        controller.handle(KeyEvent(keyCode: 0, phase: .down))
    }

    /// 미허가 동안 권한을 폴링해 부여되면 자동 활성화.
    private func startPermissionWatcher() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let denied = !AccessibilityPermission.isTrusted
            self.menuController?.setPermissionDenied(denied)
            if !denied, self.settings.enabled, self.monitor.status != .active {
                _ = self.monitor.start()
            }
        }
    }
}
