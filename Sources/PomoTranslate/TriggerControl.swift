import Cocoa

/// @user_flow 触发方式配置控件（设置页复用）
/// 一行内：[类型: 组合键/连击] → 组合键时显示录制按钮；连击时显示 [键 ▾] × [次数 ▾]。
/// 翻译和剪贴板各放一个。固定宽度约 420。
final class TriggerControl: NSView {

    // 连击可选的键：token ↔ 显示名
    static let tapKeys: [(token: String, label: String)] = [
        ("space", "空格"), ("command", "Command"), ("shift", "Shift"),
        ("control", "Control"), ("option", "Option"),
    ]
    static let tapCounts = [2, 3, 4]

    private let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let recorder = HotkeyRecorderButton(frame: .zero)
    private let keyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let timesLabel = NSTextField(labelWithString: "×")
    private let countPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        typePopup.frame = NSRect(x: 0, y: 0, width: 88, height: 26)
        typePopup.addItem(withTitle: "组合键")
        typePopup.addItem(withTitle: "连击")
        typePopup.target = self
        typePopup.action = #selector(typeChanged)
        addSubview(typePopup)

        recorder.frame = NSRect(x: 96, y: -1, width: 204, height: 28)
        addSubview(recorder)

        keyPopup.frame = NSRect(x: 96, y: 0, width: 120, height: 26)
        for k in Self.tapKeys { keyPopup.addItem(withTitle: k.label) }
        addSubview(keyPopup)

        timesLabel.frame = NSRect(x: 222, y: 3, width: 14, height: 18)
        addSubview(timesLabel)

        countPopup.frame = NSRect(x: 240, y: 0, width: 60, height: 26)
        for c in Self.tapCounts { countPopup.addItem(withTitle: "\(c) 次") }
        addSubview(countPopup)
    }

    @objc private func typeChanged() { updateVisibility() }

    private func updateVisibility() {
        let combo = typePopup.indexOfSelectedItem == 0
        recorder.isHidden = !combo
        keyPopup.isHidden = combo
        timesLabel.isHidden = combo
        countPopup.isHidden = combo
    }

    /// 载入已保存的触发配置。
    func load(type: String, comboKey: Int, comboMods: UInt, tapKey: String, tapCount: Int) {
        typePopup.selectItem(at: type == "multitap" ? 1 : 0)
        recorder.setCombo(keyCode: comboKey, modifiers: NSEvent.ModifierFlags(rawValue: comboMods))
        if let i = Self.tapKeys.firstIndex(where: { $0.token == tapKey }) { keyPopup.selectItem(at: i) }
        if let i = Self.tapCounts.firstIndex(of: tapCount) { countPopup.selectItem(at: i) }
        else { countPopup.selectItem(at: 1) }   // 默认 3 次
        updateVisibility()
    }

    // 读回当前配置
    var type: String { typePopup.indexOfSelectedItem == 1 ? "multitap" : "combo" }
    var comboKeyCode: Int { recorder.keyCode }
    var comboModifiers: UInt { recorder.modifiers.rawValue }
    var tapKey: String { Self.tapKeys[max(0, keyPopup.indexOfSelectedItem)].token }
    var tapCount: Int { Self.tapCounts[max(0, countPopup.indexOfSelectedItem)] }

    /// 生成可读描述，如 "⌘⇧J" / "连击空格 3 次" / "连击 Command 3 次"。供菜单显示。
    static func describe(type: String, comboKey: Int, comboMods: UInt, tapKey: String, tapCount: Int) -> String {
        if type == "multitap" {
            let label = tapKeys.first(where: { $0.token == tapKey })?.label ?? tapKey
            return "连击\(label) \(tapCount) 次"
        }
        return HotkeyRecorderButton.describe(keyCode: comboKey,
                                             modifiers: NSEvent.ModifierFlags(rawValue: comboMods))
    }
}
