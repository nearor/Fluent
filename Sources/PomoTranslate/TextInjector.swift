import Cocoa
import Carbon.HIToolbox
import ApplicationServices

/// @user_flow 取字 + 回填
/// 优先用「辅助功能 API」直接读写当前聚焦输入框（时序稳，不动剪贴板）；
/// 读/写不成功再退回「剪贴板模拟」(Cmd+A/C/V) 兜底。
enum TextInjector {

    // MARK: - 对外接口

    /// 抓取当前输入框文本。先试 AX，失败退剪贴板。返回 nil 表示都失败。
    static func grabFocusedText() -> String? {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        Log.write("grab: 触发，frontmost=\(front)")
        if let el = focusedElement(), let t = axReadValue(el) {
            Log.write("grab(AX) 成功: \"\(t)\"(\(t.count))")
            return t
        }
        Log.write("grab(AX) 读不到，回退剪贴板模拟")
        return clipboardGrab()
    }

    /// 把译文覆盖回当前输入框。先试 AX，失败退剪贴板。
    static func replaceFocusedText(with newText: String) {
        if let el = focusedElement(), axWriteValue(el, newText) {
            Log.write("replace(AX) 成功")
            return
        }
        Log.write("replace(AX) 写不进，回退剪贴板模拟")
        clipboardReplace(newText)
    }

    // MARK: - 剪贴板存取（供回填前后保存/恢复）
    static func savedClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
    static func restoreClipboard(_ value: String?) {
        guard let value else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    /// 把指定文本放进剪贴板并模拟 ⌘V 粘贴到当前输入框（用于剪贴板历史选择后回填）。
    /// 不做全选，直接在光标处粘贴；粘完该文本即成为当前剪贴板内容（不还原）。
    static func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(60_000)
        sendCmd(key: CGKeyCode(kVK_ANSI_V))
    }

    /// 仅发送 ⌘V（调用方已自行设置剪贴板内容），用于粘贴文本或图片历史项。
    static func sendPaste() {
        sendCmd(key: CGKeyCode(kVK_ANSI_V))
    }

    // MARK: - 辅助功能 API（AXUIElement）

    /// 取得当前聚焦的 UI 元素（输入框）。
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        if err != .success {
            Log.write("AX: 取聚焦元素失败 err=\(err.rawValue)")
            return nil
        }
        guard let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        return (f as! AXUIElement)
    }

    /// 读取元素的文本值（kAXValue）。
    private static func axReadValue(_ el: AXUIElement) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value)
        guard err == .success else {
            Log.write("AX: 读 kAXValue 失败 err=\(err.rawValue)")
            return nil
        }
        return value as? String
    }

    /// 写入元素的文本值（kAXValue），覆盖原内容。
    private static func axWriteValue(_ el: AXUIElement, _ text: String) -> Bool {
        // 先确认这个元素可写
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable)
        guard settable.boolValue else {
            Log.write("AX: kAXValue 不可写")
            return false
        }
        let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFString)
        if err != .success {
            Log.write("AX: 写 kAXValue 失败 err=\(err.rawValue)")
            return false
        }
        return true
    }

    // MARK: - 剪贴板模拟兜底

    private static func clipboardGrab() -> String? {
        let pb = NSPasteboard.general
        let beforeCount = pb.changeCount

        usleep(150_000)                        // 等三击空格的按键完全落定
        sendCmd(key: CGKeyCode(kVK_ANSI_A))    // 全选
        usleep(220_000)                        // 等选中稳定（微信较慢）
        sendCmd(key: CGKeyCode(kVK_ANSI_C))    // 复制

        var waited = 0
        let step = 50_000
        let maxWait = 1_500_000
        while pb.changeCount == beforeCount && waited < maxWait {
            usleep(useconds_t(step))
            waited += step
        }

        let changed = pb.changeCount != beforeCount
        let str = pb.string(forType: .string)
        Log.write("grab(剪贴板): changeCount \(beforeCount)->\(pb.changeCount), waited=\(waited/1000)ms, changed=\(changed), got=\(str.map { "\"\($0)\"(\($0.count))" } ?? "nil")")
        if !changed { return nil }
        return str
    }

    private static func clipboardReplace(_ newText: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(newText, forType: .string)
        usleep(80_000)
        sendCmd(key: CGKeyCode(kVK_ANSI_A))
        usleep(80_000)
        sendCmd(key: CGKeyCode(kVK_ANSI_V))
        usleep(120_000)
    }

    // MARK: - 合成按键（带 Cmd 修饰）
    private static func sendCmd(key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
