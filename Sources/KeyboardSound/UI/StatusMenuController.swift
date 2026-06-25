import AppKit

/// 메뉴바 아이콘 + 메뉴. 켜기/끄기, 프리셋, 설정 창, 권한 상태, 종료.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let settings: Settings
    private let onOpenSettings: () -> Void
    private let onOpenPermission: () -> Void

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var permissionDenied = false

    init(settings: Settings,
         onOpenSettings: @escaping () -> Void,
         onOpenPermission: @escaping () -> Void) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onOpenPermission = onOpenPermission
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyboardSound")
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    func setPermissionDenied(_ denied: Bool) {
        permissionDenied = denied
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        if permissionDenied {
            let item = NSMenuItem(title: "⚠️ 손쉬운 사용 권한 필요 — 설정 열기",
                                  action: #selector(openPermission), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: "키보드 소리", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)

        let presetMenu = NSMenu()
        for preset in Preset.all {
            let item = NSMenuItem(title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = (settings.presetID == preset.id) ? .on : .off
            presetMenu.addItem(item)
        }
        let presetParent = NSMenuItem(title: "프리셋", action: nil, keyEquivalent: "")
        menu.setSubmenu(presetMenu, for: presetParent)
        menu.addItem(presetParent)

        let settingsItem = NSMenuItem(title: "사운드 설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { settings.enabled.toggle(); rebuild() }
    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let preset = Preset.with(id: id) {
            settings.applyPreset(preset)
        }
        rebuild()
    }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openPermission() { onOpenPermission() }
    @objc private func quit() { NSApp.terminate(nil) }
}
