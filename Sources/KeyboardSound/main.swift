import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 메뉴바 전용 (Dock 아이콘 없음)
app.run()
