import Cocoa

/// 翻转坐标容器：y=0 在顶部，从上往下布局。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// @user_flow 设置界面（标签页：翻译 / 剪贴板）
/// 仿 macOS 系统设置：分区标题 + 右对齐标签 + 左对齐控件 + 统一间距。
final class SettingsWindowController: NSWindowController, NSSearchFieldDelegate {

    // 翻译页
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSComboBox()
    private let targetLangPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nativeLangPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let thinkingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let translateTrigger = TriggerControl(frame: .zero)

    // 剪贴板页
    private let clipboardEnable = NSButton(checkboxWithTitle: "启用剪贴板历史", target: nil, action: nil)
    private let historySizeField = NSTextField()
    private let clipboardTrigger = TriggerControl(frame: .zero)

    private let testResultLabel = NSTextField(labelWithString: "")

    // 布局常量
    private let labelX: CGFloat = 18, labelW: CGFloat = 116
    private let ctrlX: CGFloat = 142, ctrlW: CGFloat = 300

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Fluent 设置  v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?")
        win.center()
        self.init(window: win)
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let tabView = NSTabView(frame: NSRect(x: 8, y: 56, width: 484, height: 596))
        tabView.autoresizingMask = [.width, .height]
        let t1 = NSTabViewItem(identifier: "t"); t1.label = "翻译"; t1.view = buildTranslateTab()
        let t2 = NSTabViewItem(identifier: "c"); t2.label = "剪贴板"; t2.view = buildClipboardTab()
        tabView.addTabViewItem(t1); tabView.addTabViewItem(t2)
        content.addSubview(tabView)

        let saveBtn = NSButton(title: "保存", target: self, action: #selector(save))
        saveBtn.frame = NSRect(x: 408, y: 14, width: 80, height: 30)
        saveBtn.bezelStyle = .rounded; saveBtn.keyEquivalent = "\r"
        content.addSubview(saveBtn)

        let testBtn = NSButton(title: "测试连接", target: self, action: #selector(testConnection))
        testBtn.frame = NSRect(x: 16, y: 14, width: 96, height: 30)
        testBtn.bezelStyle = .rounded
        content.addSubview(testBtn)

        testResultLabel.frame = NSRect(x: 120, y: 17, width: 280, height: 24)
        testResultLabel.textColor = .secondaryLabelColor
        testResultLabel.lineBreakMode = .byTruncatingTail
        testResultLabel.font = NSFont.systemFont(ofSize: 11)
        content.addSubview(testResultLabel)
    }

    // 行布局工具（在给定 FlippedView 上从上往下排）
    private func makeRow(_ v: NSView, _ y: inout CGFloat, _ labelText: String, _ control: NSView, h: CGFloat = 26) {
        let l = NSTextField(labelWithString: labelText)
        l.alignment = .right; l.font = NSFont.systemFont(ofSize: 12); l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.frame = NSRect(x: labelX, y: y + (h - 16) / 2, width: labelW, height: 16)
        v.addSubview(l)
        control.frame = NSRect(x: ctrlX, y: y, width: ctrlW, height: h)
        v.addSubview(control)
        y += h + 12
    }
    private func makeSection(_ v: NSView, _ y: inout CGFloat, _ title: String) {
        y += 8
        let l = NSTextField(labelWithString: title)
        l.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        l.frame = NSRect(x: 14, y: y, width: 450, height: 18)
        v.addSubview(l)
        y += 28
    }

    private func buildTranslateTab() -> NSView {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: 470, height: 600))
        var y: CGFloat = 16

        makeSection(v, &y, "AI 服务")
        makeRow(v, &y, "厂商", presetPopup)
        presetPopup.target = self; presetPopup.action = #selector(presetChanged)
        for p in providerPresets { presetPopup.addItem(withTitle: p.label) }
        makeRow(v, &y, "API 协议", providerPopup)
        for p in AIProvider.allCases { providerPopup.addItem(withTitle: p.displayName) }
        makeRow(v, &y, "API 地址", baseURLField)
        makeRow(v, &y, "API Key", apiKeyField)
        makeRow(v, &y, "模型", modelField); modelField.completes = true

        makeSection(v, &y, "翻译选项")
        makeRow(v, &y, "外语方向", targetLangPopup)
        makeRow(v, &y, "母语方向", nativeLangPopup)
        for l in supportedLanguages { targetLangPopup.addItem(withTitle: l.label); nativeLangPopup.addItem(withTitle: l.label) }
        makeRow(v, &y, "翻译风格", stylePopup)
        for s in translationStyles { stylePopup.addItem(withTitle: s.label) }
        makeRow(v, &y, "翻译质量", qualityPopup)
        qualityPopup.addItem(withTitle: "高质量（反思）"); qualityPopup.addItem(withTitle: "快速（单次）")
        makeRow(v, &y, "思考强度", thinkingPopup)
        for t in ["跟随模型默认", "关闭（最快）", "轻量（推荐）", "中等", "深度（最准）"] { thinkingPopup.addItem(withTitle: t) }

        makeSection(v, &y, "触发方式")
        makeRow(v, &y, "触发", translateTrigger, h: 30)

        return v
    }

    private func buildClipboardTab() -> NSView {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: 470, height: 600))
        var y: CGFloat = 16

        makeSection(v, &y, "剪贴板历史")
        clipboardEnable.frame = NSRect(x: ctrlX, y: y, width: ctrlW, height: 22); v.addSubview(clipboardEnable); y += 34
        makeRow(v, &y, "保留条数", historySizeField)
        let hint = NSTextField(labelWithString: "范围 10–500")
        hint.font = NSFont.systemFont(ofSize: 11); hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: ctrlX, y: y - 6, width: ctrlW, height: 14); v.addSubview(hint); y += 14

        makeSection(v, &y, "触发方式")
        makeRow(v, &y, "触发", clipboardTrigger, h: 30)
        let tip = NSTextField(wrappingLabelWithString: "「连击」可设连按 Command / Shift 等修饰键 N 次；「组合键」可录制如 ⌥⌘V。")
        tip.font = NSFont.systemFont(ofSize: 11); tip.textColor = .tertiaryLabelColor
        tip.frame = NSRect(x: ctrlX, y: y, width: ctrlW, height: 36); v.addSubview(tip)

        return v
    }

    // MARK: - 厂商联动
    @objc private func presetChanged() {
        applyPreset(providerPresets[max(0, presetPopup.indexOfSelectedItem)], fillDefaults: true)
    }
    private func currentPreset() -> ProviderPreset { providerPresets[max(0, presetPopup.indexOfSelectedItem)] }

    private func applyPreset(_ preset: ProviderPreset, fillDefaults: Bool) {
        if preset.isCustom {
            providerPopup.isEnabled = true
        } else {
            if let idx = AIProvider.allCases.firstIndex(of: preset.protocolType) { providerPopup.selectItem(at: idx) }
            providerPopup.isEnabled = false
            if fillDefaults { baseURLField.stringValue = preset.baseURL }
        }
        modelField.removeAllItems()
        modelField.addItems(withObjectValues: preset.models)
        modelField.placeholderString = preset.modelHint.isEmpty ? "手动填模型名" : preset.modelHint
        if fillDefaults { modelField.stringValue = preset.models.first ?? "" }
        // 思考强度对不支持的厂商无效：切到这类厂商时复位为「跟随默认」
        if !preset.supportsThinking && fillDefaults { thinkingPopup.selectItem(at: 0) }
        thinkingPopup.isEnabled = preset.supportsThinking
    }

    private func currentPresetIndex() -> Int {
        let c = AppConfig.shared
        if !c.providerPreset.isEmpty, let i = providerPresets.firstIndex(where: { $0.label == c.providerPreset }) { return i }
        if let i = providerPresets.firstIndex(where: { !$0.isCustom && $0.baseURL == c.baseURL }) { return i }
        return providerPresets.firstIndex(where: { $0.isCustom }) ?? 0
    }

    // MARK: - 测试连接
    @objc private func testConnection() {
        let backup = AppConfig.shared.makeSnapshot()
        saveValues()
        testResultLabel.textColor = .secondaryLabelColor
        testResultLabel.stringValue = "测试中…"
        Task { @MainActor in
            defer { AppConfig.shared.restore(backup) }
            do {
                let result = try await AIClient.translate("你好")
                let preview = result.count > 20 ? String(result.prefix(20)) + "…" : result
                testResultLabel.textColor = .systemGreen
                testResultLabel.stringValue = "✓ 连接成功：\(preview)"
            } catch {
                testResultLabel.textColor = .systemRed
                testResultLabel.stringValue = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func loadValues() {
        let c = AppConfig.shared
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: c.provider) ?? 0)
        baseURLField.stringValue = c.baseURL
        apiKeyField.stringValue = c.apiKey
        selectLang(targetLangPopup, name: c.targetLang)
        selectLang(nativeLangPopup, name: c.nativeLang)
        stylePopup.selectItem(withTitle: c.style)
        if stylePopup.indexOfSelectedItem < 0 { stylePopup.selectItem(at: 0) }
        qualityPopup.selectItem(at: c.useReflection ? 0 : 1)
        switch c.thinkingMode {
        case "off", "disabled": thinkingPopup.selectItem(at: 1)
        case "low":             thinkingPopup.selectItem(at: 2)
        case "medium":          thinkingPopup.selectItem(at: 3)
        case "high", "enabled": thinkingPopup.selectItem(at: 4)
        default:                thinkingPopup.selectItem(at: 0)
        }

        let idx = currentPresetIndex()
        presetPopup.selectItem(at: idx)
        applyPreset(providerPresets[idx], fillDefaults: false)
        modelField.stringValue = c.model

        translateTrigger.load(type: c.translateTriggerType, comboKey: c.hotkeyKeyCode, comboMods: c.hotkeyModifiers,
                              tapKey: c.translateMultitapKey, tapCount: c.translateMultitapCount)
        clipboardTrigger.load(type: c.clipboardTriggerType, comboKey: c.clipboardHotkeyKeyCode, comboMods: c.clipboardHotkeyModifiers,
                              tapKey: c.clipboardMultitapKey, tapCount: c.clipboardMultitapCount)

        clipboardEnable.state = c.clipboardEnabled ? .on : .off
        historySizeField.stringValue = String(c.clipboardHistorySize)
    }

    private func selectLang(_ popup: NSPopUpButton, name: String) {
        popup.selectItem(withTitle: languageLabel(forName: name))
        if popup.indexOfSelectedItem < 0 { popup.selectItem(at: 0) }
    }

    @objc private func save() { saveValues(); window?.close() }

    private func saveValues() {
        let c = AppConfig.shared
        c.providerPreset = currentPreset().label
        c.provider = AIProvider.allCases[providerPopup.indexOfSelectedItem]
        c.baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespaces)
        c.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        c.model = modelField.stringValue.trimmingCharacters(in: .whitespaces)
        c.targetLang = supportedLanguages[max(0, targetLangPopup.indexOfSelectedItem)].name
        c.nativeLang = supportedLanguages[max(0, nativeLangPopup.indexOfSelectedItem)].name
        c.style = translationStyles[max(0, stylePopup.indexOfSelectedItem)].label
        c.useReflection = (qualityPopup.indexOfSelectedItem == 0)
        switch thinkingPopup.indexOfSelectedItem {
        case 1: c.thinkingMode = "off"
        case 2: c.thinkingMode = "low"
        case 3: c.thinkingMode = "medium"
        case 4: c.thinkingMode = "high"
        default: c.thinkingMode = "default"
        }
        c.translateTriggerType = translateTrigger.type
        c.hotkeyKeyCode = translateTrigger.comboKeyCode
        c.hotkeyModifiers = translateTrigger.comboModifiers
        c.translateMultitapKey = translateTrigger.tapKey
        c.translateMultitapCount = translateTrigger.tapCount
        c.clipboardTriggerType = clipboardTrigger.type
        c.clipboardHotkeyKeyCode = clipboardTrigger.comboKeyCode
        c.clipboardHotkeyModifiers = clipboardTrigger.comboModifiers
        c.clipboardMultitapKey = clipboardTrigger.tapKey
        c.clipboardMultitapCount = clipboardTrigger.tapCount
        c.clipboardEnabled = (clipboardEnable.state == .on)
        if let n = Int(historySizeField.stringValue.trimmingCharacters(in: .whitespaces)), n >= 10 {
            c.clipboardHistorySize = min(n, 500)
        }
    }

    func show() {
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
