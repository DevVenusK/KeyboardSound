import AppKit
import Combine
import os

private let appLog = Logger(subsystem: "com.keyboardsound.app", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let player = SoundPlayer()
    private let samplePlayer = SamplePlayer()
    private let monitor = KeyEventMonitor()

    private var bank: ClickSoundBank!
    private var sampleStore: CustomSampleStore!
    private var controller: KeySoundController!
    private var menuController: StatusMenuController!
    private var settingsWindow: SettingsWindowController!

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?
    private var activityToken: NSObjectProtocol?
    private var lastInputMonitoringGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App Nap 방지: 메뉴바 전용 앱이 백그라운드에서 잠들면 메인 런루프가 멈춰
        // CGEventTap이 죽는다. 토큰을 앱 수명 동안 유지해 항상 깨어있게 한다.
        // (시스템 유휴 잠자기는 허용 — 키보드 사운드 앱이 맥을 깨워둘 이유는 없음)
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Global keyboard sound playback"
        )

        bank = ClickSoundBank(format: player.format,
                              tone: settings.tone,
                              sharpness: settings.sharpness,
                              weight: settings.weight,
                              ring: settings.ring,
                              preset: settings.currentSwitch)
        sampleStore = CustomSampleStore(format: samplePlayer.format)
        sampleStore.loadPersisted()

        controller = KeySoundController(settings: settings, bank: bank, player: player,
                                        sampleStore: sampleStore, samplePlayer: samplePlayer)
        monitor.onEvent = { [weak self] event in self?.controller.handle(event) }

        settingsWindow = SettingsWindowController(settings: settings, sampleStore: sampleStore) { [weak self] in
            self?.playTestSound()
        }
        menuController = StatusMenuController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onOpenPermission: { InputPermissions.openSettings() }
        )

        // 톤/샤프함/무게/울림/스위치 변경 → 뱅크 재생성. 5개 신호를 Void로 병합 후 디바운스.
        let changeSignals: [AnyPublisher<Void, Never>] = [
            settings.$tone.map { _ in () }.eraseToAnyPublisher(),
            settings.$sharpness.map { _ in () }.eraseToAnyPublisher(),
            settings.$weight.map { _ in () }.eraseToAnyPublisher(),
            settings.$ring.map { _ in () }.eraseToAnyPublisher(),
            settings.$selectedSwitchID.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changeSignals)
            .dropFirst()
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.regenerateBank() }
            .store(in: &cancellables)

        // enabled 변경 → 시작/정지
        settings.$enabled
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
            .store(in: &cancellables)

        if !InputPermissions.isInputMonitoringGranted {
            InputPermissions.requestInputMonitoring()
        }
        setEnabled(settings.enabled)
        lastInputMonitoringGranted = InputPermissions.isInputMonitoringGranted
        startPermissionWatcher()
    }

    private func regenerateBank() {
        // 커스텀 모드에선 합성 뱅크를 쓰지 않으므로 재생성 불필요.
        guard settings.selectedSwitchID != Preset.customID else { return }
        bank.regenerate(tone: settings.tone, sharpness: settings.sharpness, weight: settings.weight, ring: settings.ring, preset: settings.currentSwitch)
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            let audioOK = player.start()
            let status = monitor.start()
            let granted = InputPermissions.isInputMonitoringGranted
            // 탭 생성 성공(.active)이어도 입력 모니터링 권한이 없으면 keyDown은 안 들어온다(거짓 양성).
            // 실제 동작 여부는 탭 상태가 아니라 권한으로 판정한다.
            appLog.notice("setEnabled(true) inputMonitoring=\(granted, privacy: .public) audioStart=\(audioOK, privacy: .public) tapStatus=\(String(describing: status), privacy: .public)")
            menuController?.setPermissionDenied(!granted)
        } else {
            appLog.notice("setEnabled(false)")
            monitor.stop()
            player.stop()
        }
    }

    private func playTestSound() {
        // 테스트 소리는 오디오 버퍼 재생일 뿐 키 이벤트와 무관하므로 권한 게이팅이 필요 없다.
        guard settings.enabled else { return }
        controller.handle(KeyEvent(keyCode: 0, phase: .down))
    }

    /// 미허가 동안 입력 모니터링 권한을 폴링하고, 부여되는 순간 탭을 재생성한다.
    private func startPermissionWatcher() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = InputPermissions.isInputMonitoringGranted
            self.menuController?.setPermissionDenied(!granted)

            // 권한이 막 부여된 순간: 권한 없이 만들어졌던 탭은 keyDown을 못 받는 거짓 양성
            // (.active)이므로, 탭을 stop→start로 재생성해 새 권한으로 다시 연다.
            if granted, !self.lastInputMonitoringGranted, self.settings.enabled {
                self.monitor.stop()
                let status = self.monitor.start()
                appLog.notice("inputMonitoring granted → monitor recreated → \(String(describing: status), privacy: .public)")
            }
            self.lastInputMonitoringGranted = granted
        }
    }
}
