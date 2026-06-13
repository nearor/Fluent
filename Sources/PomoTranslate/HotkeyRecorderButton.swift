import Cocoa

/// @user_flow 快捷键录制
/// 点一下进入录制态，按下任意「修饰键 + 主键」的组合即捕获并显示（如 ⌘⇧J）。
/// 按 Esc 取消。为避免误触发，必须至少带一个修饰键（⌘/⇧/⌃/⌥）。
final class HotkeyRecorderButton: NSButton {

    /// 捕获到新组合时回调：(keyCode, 修饰键)。
    var onCapture: ((Int, NSEvent.ModifierFlags) -> Void)?

    private(set) var keyCode: Int = 38                       // 默认 J
    private(set) var modifiers: NSEvent.ModifierFlags = [.command, .shift]

    private var recording = false { didSet { updateTitle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    /// 外部注入当前已保存的快捷键。
    func setCombo(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        updateTitle()
    }

    @objc private func toggleRecording() {
        recording.toggle()
        if recording { window?.makeFirstResponder(self) }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    // 普通按键走 keyDown
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        capture(event)
    }

    // 带 ⌘ 的组合会走 performKeyEquivalent，录制态下也要拦下来
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // Esc 取消
        if event.keyCode == 53 {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard !mods.isEmpty else {
            // 没带修饰键，拒绝（否则会满键盘误触发）
            NSSound.beep()
            return
        }
        keyCode = Int(event.keyCode)
        modifiers = mods
        recording = false
        window?.makeFirstResponder(nil)
        onCapture?(keyCode, mods)
        updateTitle()
    }

    private func updateTitle() {
        title = recording ? "按下快捷键…（Esc 取消）"
                          : Self.describe(keyCode: keyCode, modifiers: modifiers)
    }

    /// 把 keyCode + 修饰键转成可读字符串，如 ⌘⇧J。
    static func describe(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    /// 常用 keyCode → 显示名。覆盖字母、数字、方向键及常见特殊键。
    static func keyName(_ code: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[code] ?? "Key\(code)"
    }
}
