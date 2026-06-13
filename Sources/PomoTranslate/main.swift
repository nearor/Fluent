import Cocoa

// 菜单栏 app 入口：以 accessory 模式运行（无 Dock 图标）。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
