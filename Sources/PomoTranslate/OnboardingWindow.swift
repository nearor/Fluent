import Cocoa

/// @user_flow 首次安装引导
/// 分 3 步引导用户完成授权与配置，每步实时显示状态：
///   ① 辅助功能权限  ② 输入监控权限  ③ AI API 配置
/// 授权辅助功能后，app 会自动重启使权限生效（无需手动退出再打开）。
final class OnboardingWindowController: NSWindowController {

    // 由 AppDelegate 注入的动作
    var onOpenAccessibility: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRecheck: (() -> Void)?        // 重启监听 + 刷新

    private var refreshTimer: Timer?

    // 两步的状态行（辅助功能 + API 配置）
    private let axStatus = NSTextField(labelWithString: "")
    private let apiStatus = NSTextField(labelWithString: "")
    private let summary = NSTextField(labelWithString: "")

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Fluent 初次设置"
        win.center()
        self.init(window: win)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "欢迎使用 Fluent 👋")
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        title.frame = NSRect(x: 24, y: 372, width: 472, height: 28)
        content.addSubview(title)

        let intro = NSTextField(wrappingLabelWithString:
            "三击空格翻译需要「辅助功能」权限，加上一次 AI 配置。完成下面两步即可。授权辅助功能后 app 会自动重启使其生效。")
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.frame = NSRect(x: 24, y: 326, width: 472, height: 40)
        content.addSubview(intro)

        buildStep(content, y: 244,
                  index: "①",
                  name: "辅助功能权限",
                  desc: "用于监听三击空格 + 把译文写回输入框",
                  statusField: axStatus,
                  buttonTitle: "打开辅助功能设置",
                  action: #selector(openAX))

        buildStep(content, y: 144,
                  index: "②",
                  name: "AI API 配置",
                  desc: "填入你自己的 DeepSeek / 豆包 / Claude key",
                  statusField: apiStatus,
                  buttonTitle: "打开配置",
                  action: #selector(openAPI))

        summary.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        summary.frame = NSRect(x: 24, y: 70, width: 472, height: 22)
        content.addSubview(summary)

        let recheckBtn = NSButton(title: "我已授权，重新检测", target: self, action: #selector(recheck))
        recheckBtn.frame = NSRect(x: 24, y: 16, width: 180, height: 30)
        recheckBtn.bezelStyle = .rounded
        content.addSubview(recheckBtn)

        let doneBtn = NSButton(title: "完成", target: self, action: #selector(done))
        doneBtn.frame = NSRect(x: 416, y: 16, width: 80, height: 30)
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        content.addSubview(doneBtn)
    }

    private func buildStep(_ content: NSView, y: CGFloat, index: String, name: String,
                           desc: String, statusField: NSTextField,
                           buttonTitle: String, action: Selector) {
        let nameLabel = NSTextField(labelWithString: "\(index) \(name)")
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameLabel.frame = NSRect(x: 24, y: y + 36, width: 300, height: 22)
        content.addSubview(nameLabel)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 24, y: y + 14, width: 320, height: 18)
        content.addSubview(descLabel)

        statusField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusField.frame = NSRect(x: 24, y: y - 8, width: 320, height: 18)
        content.addSubview(statusField)

        let btn = NSButton(title: buttonTitle, target: self, action: action)
        btn.frame = NSRect(x: 336, y: y + 12, width: 160, height: 28)
        btn.bezelStyle = .rounded
        content.addSubview(btn)
    }

    // MARK: - 状态刷新
    func refresh() {
        let ax = HotkeyDetector.hasAccessibilityPermission(prompt: false)
        let api = AppConfig.shared.isConfigured

        axStatus.attributedStringValue = statusText(ax)
        apiStatus.attributedStringValue = statusText(api)

        if ax && api {
            summary.textColor = .systemGreen
            summary.stringValue = "✓ 全部就绪！现在可在任意输入框三击空格翻译。"
        } else {
            summary.textColor = .systemOrange
            summary.stringValue = "还差几步，完成后点「重新检测」。"
        }
    }

    private func statusText(_ ok: Bool) -> NSAttributedString {
        let s = ok ? "● 已完成" : "○ 待完成"
        let color: NSColor = ok ? .systemGreen : .systemRed
        return NSAttributedString(string: s, attributes: [.foregroundColor: color])
    }

    // MARK: - Actions
    @objc private func openAX() { onOpenAccessibility?() }
    @objc private func openAPI() { onOpenSettings?() }

    @objc private func recheck() {
        onRecheck?()
        refresh()
    }

    @objc private func done() {
        AppConfig.shared.onboardingDone = true
        window?.close()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func windowWillCloseCleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
