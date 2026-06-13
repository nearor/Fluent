import Cocoa

/// 菜单栏 app 主控制器：把番茄钟、翻译触发、设置窗口串起来。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let detector = HotkeyDetector()
    private var settingsWC: SettingsWindowController?
    private var onboardingWC: OnboardingWindowController?
    private var clipboardWC: ClipboardHistoryWindowController?
    /// 呼出历史面板前记下的前台 app，用于选完后把焦点还回去再粘贴。
    private var clipboardPrevApp: NSRunningApplication?

    private var isTranslating = false
    private var detectorStarted = false
    /// 启动那一刻是否已有辅助功能权限。CGEventTap 的权限在进程启动时被 TCC 缓存，
    /// 若启动时没有、运行中才授予，必须重启进程才生效（同进程内重建 tap 无效）。
    private var hadAXAtLaunch = false
    /// 自动重启只触发一次的保险丝。
    private var didScheduleRelaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        hadAXAtLaunch = HotkeyDetector.hasAccessibilityPermission(prompt: false)
        installMainMenu()
        setupStatusItem()
        setupDetector()
        ClipboardHistory.shared.start()   // 剪贴板历史轮询（记录与否由配置 clipboardEnabled 控制）
        // 权限可能在启动后才授予：定时刷新菜单状态；一旦检测到刚拿到辅助功能权限，自动重启进程使其生效
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.relaunchIfPermissionJustGranted()
            self?.rebuildMenu()
        }
        // 首次启动或尚未就绪时：主动请求辅助功能权限（自动登记进列表 + 弹授权框），再弹引导
        if !AppConfig.shared.onboardingDone || !isFullyReady() {
            HotkeyDetector.requestAccessibilityPermission()
            showOnboarding()
        }
    }

    /// 就绪条件：辅助功能 + API 配置即可。
    /// （三击空格用的是主动式事件监听 .defaultTap，只需辅助功能权限，不需要输入监控）
    private func isFullyReady() -> Bool {
        HotkeyDetector.hasAccessibilityPermission(prompt: false)
            && AppConfig.shared.isConfigured
    }

    // MARK: - 主菜单（让设置窗口里的输入框支持 ⌘A/⌘C/⌘V/⌘X/⌘Z）
    /// accessory app 默认没有主菜单，文本框的标准编辑快捷键就失效了。
    /// 这里挂一个含「编辑」菜单的主菜单，动作 target 为 nil → 沿响应链发给当前输入框。
    /// 顶部不会真的显示菜单栏（accessory app 特性），只是让快捷键能被分发。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单（占位 + 退出）
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Fluent",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // 编辑菜单：标准编辑动作 + 快捷键
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 菜单栏
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon()
        rebuildMenu()
    }

    /// 菜单栏图标：用 SF Symbol 模板图（单色，跟随深浅色），翻译主题的对话气泡。
    private func setStatusIcon() {
        if let img = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Fluent") {
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.title = ""
        } else {
            statusItem.button?.title = "🌐"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let cfg = AppConfig.shared

        // 版本头
        let verItem = NSMenuItem(title: "Fluent  v\(Self.appVersion())", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        menu.addItem(verItem)
        menu.addItem(.separator())

        // 翻译区
        menu.addItem(sectionTitle("翻译"))

        let axOK = HotkeyDetector.hasAccessibilityPermission(prompt: false)
        let ready = cfg.isConfigured && axOK
        let trig = TriggerControl.describe(
            type: cfg.translateTriggerType,
            comboKey: cfg.hotkeyKeyCode, comboMods: cfg.hotkeyModifiers,
            tapKey: cfg.translateMultitapKey, tapCount: cfg.translateMultitapCount)
        let status: String
        if ready { status = "就绪 ✓ · \(trig)" }
        else if !cfg.isConfigured { status = "未配置 API ⚠️ 见设置" }
        else { status = "缺辅助功能权限 ⚠️ 见权限引导" }
        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        // 译入语言子菜单
        let langItem = NSMenuItem(title: "译入语言：\(languageLabel(forName: cfg.targetLang))", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in supportedLanguages {
            let mi = NSMenuItem(title: lang.label, action: #selector(selectTargetLang(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = lang.name
            mi.state = (lang.name == cfg.targetLang) ? .on : .off
            langMenu.addItem(mi)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // 翻译风格子菜单
        let styleItem = NSMenuItem(title: "翻译风格：\(cfg.style)", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for s in translationStyles {
            let mi = NSMenuItem(title: s.label, action: #selector(selectStyle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = s.label
            mi.state = (s.label == cfg.style) ? .on : .off
            styleMenu.addItem(mi)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        // 质量切换
        let qualityItem = NSMenuItem(title: "高质量模式（反思，较慢）", action: #selector(toggleQuality), keyEquivalent: "")
        qualityItem.target = self
        qualityItem.state = cfg.useReflection ? .on : .off
        menu.addItem(qualityItem)

        menu.addItem(item("翻译当前输入框", #selector(manualTranslate), symbol: "text.bubble"))

        menu.addItem(.separator())

        // 剪贴板历史区
        menu.addItem(sectionTitle("剪贴板历史"))
        let clipTrig = TriggerControl.describe(
            type: cfg.clipboardTriggerType,
            comboKey: cfg.clipboardHotkeyKeyCode, comboMods: cfg.clipboardHotkeyModifiers,
            tapKey: cfg.clipboardMultitapKey, tapCount: cfg.clipboardMultitapCount)
        if cfg.clipboardEnabled {
            menu.addItem(item("打开历史面板（\(clipTrig)）", #selector(showClipboardHistory), symbol: "doc.on.clipboard"))
            menu.addItem(item("清空历史", #selector(clearClipboardHistory), symbol: "trash"))
        } else {
            let off = NSMenuItem(title: "已关闭（见设置）", action: nil, keyEquivalent: "")
            off.isEnabled = false
            menu.addItem(off)
        }

        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(openSettings), symbol: "gearshape"))
        menu.addItem(item("权限引导 / 重新检测…", #selector(showOnboarding), symbol: "checkmark.shield"))
        menu.addItem(item("退出 Fluent", #selector(quit), symbol: "power"))

        // 注意：这里必须挂到菜单栏 statusItem，不能写成局部变量
        self.statusItem.menu = menu
    }

    // MARK: - 菜单快捷切换
    @objc private func selectTargetLang(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        AppConfig.shared.targetLang = name
        rebuildMenu()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        AppConfig.shared.style = label
        rebuildMenu()
    }

    @objc private func toggleQuality() {
        AppConfig.shared.useReflection.toggle()
        rebuildMenu()
    }

    private func sectionTitle(_ t: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: t)
        }
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ sel: Selector, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            i.image = img
        }
        return i
    }

    // MARK: - 翻译触发
    private func setupDetector() {
        detector.onTrigger = { [weak self] in self?.handleTranslateTrigger() }
        detector.onClipboardHotkey = { [weak self] in self?.showClipboardHistory() }
        // 静默尝试启动；授权引导交给 onboarding 窗口
        detectorStarted = detector.start()
        rebuildMenu()
    }

    // MARK: - 剪贴板历史
    @objc private func showClipboardHistory() {
        guard AppConfig.shared.clipboardEnabled else { return }
        // 记下当前前台 app，选完后焦点要还给它再粘贴
        clipboardPrevApp = NSWorkspace.shared.frontmostApplication

        if clipboardWC == nil {
            let wc = ClipboardHistoryWindowController()
            wc.onSelect = { [weak self] item in self?.pasteFromHistory(item) }
            wc.onDelete = { item in ClipboardHistory.shared.remove(item) }
            clipboardWC = wc
        }
        clipboardWC?.present(items: ClipboardHistory.shared.items)
    }

    /// 选中历史项：写回剪贴板（文本或图片），把焦点还给原 app，再模拟粘贴。
    private func pasteFromHistory(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image(let data, let type, _, _):
            pb.setData(data, forType: type)
        }
        clipboardPrevApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TextInjector.sendPaste()
        }
    }

    @objc private func clearClipboardHistory() {
        ClipboardHistory.shared.clear()
    }

    /// 手动触发翻译（菜单点击），用于诊断：绕开键盘监听，直接测取字+翻译+回填。
    /// 延迟 0.4 秒，等菜单关闭、焦点回到目标 app 的输入框，再取字。
    @objc private func manualTranslate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.handleTranslateTrigger()
        }
    }

    private func handleTranslateTrigger() {
        guard !isTranslating else { return }
        guard AppConfig.shared.isConfigured else {
            HUDOverlay.shared.showResult(success: false, text: "还没配置 API key")
            openSettings()
            return
        }
        isTranslating = true
        ClipboardHistory.shared.suspended = true   // 翻译期间暂停记录，避免取字/回填污染历史
        HUDOverlay.shared.showLoading("翻译中…")

        // 保存用户原剪贴板（主线程读）
        let savedClip = TextInjector.savedClipboard()

        // 取字 + 翻译 + 回填全部放后台，避免阻塞主线程导致 HUD 卡住
        Task.detached { [weak self] in
            guard let self else { return }
            guard let raw = TextInjector.grabFocusedText() else {
                await MainActor.run { self.finishTranslate(restore: savedClip, error: "没抓到输入框内容") }
                return
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                await MainActor.run { self.finishTranslate(restore: savedClip, error: "输入框是空的") }
                return
            }
            do {
                Log.write("translate: 发给AI的文本=\"\(text)\"")
                let translated = try await AIClient.translate(text)
                Log.write("translate: AI返回=\"\(translated)\"")
                TextInjector.replaceFocusedText(with: translated)
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run { self.finishTranslate(restore: savedClip, error: nil) }
            } catch {
                Log.write("translate: 出错 \(error.localizedDescription)")
                await MainActor.run { self.finishTranslate(restore: savedClip, error: error.localizedDescription) }
            }
        }
    }

    private func finishTranslate(restore: String?, error: String?) {
        TextInjector.restoreClipboard(restore)
        isTranslating = false
        // 还原剪贴板后稍等再恢复历史记录，跳过这次还原带来的变动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            ClipboardHistory.shared.suspended = false
        }
        if let error {
            HUDOverlay.shared.showResult(success: false, text: error)
        } else {
            HUDOverlay.shared.showResult(success: true, text: "已翻译")
        }
    }

    // MARK: - 设置
    @objc private func openSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController() }
        settingsWC?.show()
        rebuildMenu()
    }

    // MARK: - 首次引导
    @objc private func showOnboarding() {
        if onboardingWC == nil {
            let wc = OnboardingWindowController()
            wc.onOpenAccessibility = { [weak self] in self?.openAccessibilityPane() }
            wc.onOpenSettings = { [weak self] in self?.openSettings() }
            wc.onRecheck = { [weak self] in self?.restartDetector() }
            onboardingWC = wc
        }
        onboardingWC?.show()
    }

    /// 授权后让监听生效。
    /// 启动时无权限、运行中才授予的情况，CGEventTap 必须重启进程才生效，这里自动重启；
    /// 其余情况（启动时本就有权限）同进程内重建 tap 即可。
    private func restartDetector() {
        if relaunchIfPermissionJustGranted() { return }
        if !HotkeyDetector.hasAccessibilityPermission(prompt: false) {
            HUDOverlay.shared.showResult(success: false, text: "辅助功能权限还没给")
        }
        detectorStarted = detector.restart()
        rebuildMenu()
    }

    /// 若「启动时无权限、现在已授权」，自动重启整个 app 使 CGEventTap 生效。
    /// 返回是否已触发重启。
    @discardableResult
    private func relaunchIfPermissionJustGranted() -> Bool {
        guard !didScheduleRelaunch, !hadAXAtLaunch else { return false }
        guard HotkeyDetector.hasAccessibilityPermission(prompt: false) else { return false }
        didScheduleRelaunch = true
        notify("辅助功能已授权，正在自动重启以生效…")
        relaunchApp()
        return true
    }

    /// 重启自身：等当前进程退出后再用 open 拉起新实例，避免 LaunchServices 误判为仍在运行。
    private func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(bundlePath)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func openAccessibilityPane() {
        // 先请求：让 app 自动出现在列表并弹系统授权框
        HotkeyDetector.requestAccessibilityPermission()
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// 应用版本号（取自 Info.plist 的 CFBundleShortVersionString，单一来源）。
    static func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    // MARK: - 通知
    private func notify(_ text: String) {
        let n = NSUserNotification()
        n.title = "Fluent"
        n.informativeText = text
        NSUserNotificationCenter.default.deliver(n)
    }
}
