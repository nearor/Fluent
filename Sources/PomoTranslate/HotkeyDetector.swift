import Cocoa
import Carbon.HIToolbox
import IOKit.hid

/// @business_rule 触发方式（统一引擎）
/// 每个动作（翻译 / 剪贴板）可配一种触发：
///   - combo（组合键）：修饰键 + 主键，如 ⌘⇧J、⌥⌘V。
///   - multitap（连击）：同一个键快速连按 N 次，如 空格×3、Command×3、Shift×2。
/// 连击的"键"支持：space / command / shift / control / option。
/// 实现：CGEventTap 同时监听 keyDown 与 flagsChanged（后者用于检测修饰键连按）。
/// 需要「辅助功能」权限。
final class HotkeyDetector {

    /// 翻译触发回调（主线程）。
    var onTrigger: (() -> Void)?
    /// 剪贴板历史触发回调（主线程）。
    var onClipboardHotkey: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    private let spaceKey = CGKeyCode(kVK_Space)
    private var previousFlags: CGEventFlags = []

    // 连击计时参数
    private let maxGap: TimeInterval = 0.4
    private let confirmDelay: TimeInterval = 0.28

    /// 连击计数状态（每个动作一份）。
    private final class TapState {
        var count = 0
        var last: TimeInterval = 0
        var work: DispatchWorkItem?
    }
    private let translateTap = TapState()
    private let clipboardTap = TapState()

    // MARK: - 启停
    func start() -> Bool {
        if isRunning { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let d = Unmanaged<HotkeyDetector>.fromOpaque(refcon).takeUnretainedValue()
                return d.handle(type: type, event: event)
            }, userInfo: refcon
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; runLoopSource = nil; isRunning = false
    }

    @discardableResult
    func restart() -> Bool { stop(); return start() }

    // MARK: - 事件处理
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let cfg = AppConfig.shared
        let clipOn = cfg.clipboardEnabled

        if type == .flagsChanged {
            let newly = newlyPressed(event.flags)
            previousFlags = event.flags
            for mod in newly {
                if cfg.translateTriggerType == "multitap", token(cfg.translateMultitapKey, matches: mod) {
                    tap(translateTap, need: cfg.translateMultitapCount) { [weak self] in self?.fireTranslate() }
                }
                if clipOn, cfg.clipboardTriggerType == "multitap", token(cfg.clipboardMultitapKey, matches: mod) {
                    tap(clipboardTap, need: cfg.clipboardMultitapCount) { [weak self] in self?.fireClipboard() }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // 真实按键会打断"修饰键连击"，重置之
        if cfg.translateTriggerType == "multitap", isModifierToken(cfg.translateMultitapKey) { reset(translateTap) }
        if cfg.clipboardTriggerType == "multitap", isModifierToken(cfg.clipboardMultitapKey) { reset(clipboardTap) }

        // 组合键
        if cfg.translateTriggerType == "combo",
           keyCode == CGKeyCode(cfg.hotkeyKeyCode),
           modifiersMatch(flags, required: NSEvent.ModifierFlags(rawValue: cfg.hotkeyModifiers)) {
            fireTranslate(); return nil
        }
        if clipOn, cfg.clipboardTriggerType == "combo",
           keyCode == CGKeyCode(cfg.clipboardHotkeyKeyCode),
           modifiersMatch(flags, required: NSEvent.ModifierFlags(rawValue: cfg.clipboardHotkeyModifiers)) {
            fireClipboard(); return nil
        }

        // 连击：空格（或其它普通键，目前只暴露 space）
        if cfg.translateTriggerType == "multitap", cfg.translateMultitapKey == "space" {
            if keyCode == spaceKey { tap(translateTap, need: cfg.translateMultitapCount) { [weak self] in self?.fireTranslate() } }
            else { reset(translateTap) }
        }
        if clipOn, cfg.clipboardTriggerType == "multitap", cfg.clipboardMultitapKey == "space" {
            if keyCode == spaceKey { tap(clipboardTap, need: cfg.clipboardMultitapCount) { [weak self] in self?.fireClipboard() } }
            else { reset(clipboardTap) }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 连击计数
    private func tap(_ s: TapState, need: Int, fire: @escaping () -> Void) {
        let now = Date().timeIntervalSince1970
        s.count = (s.count > 0 && now - s.last <= maxGap) ? s.count + 1 : 1
        s.last = now
        s.work?.cancel()
        let w = DispatchWorkItem {
            if s.count == need { fire() }
            s.count = 0
        }
        s.work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmDelay, execute: w)
    }
    private func reset(_ s: TapState) { s.work?.cancel(); s.count = 0 }

    private func fireTranslate() { DispatchQueue.main.async { [weak self] in self?.onTrigger?() } }
    private func fireClipboard() { DispatchQueue.main.async { [weak self] in self?.onClipboardHotkey?() } }

    // MARK: - 修饰键工具
    private func newlyPressed(_ flags: CGEventFlags) -> [NSEvent.ModifierFlags] {
        var res: [NSEvent.ModifierFlags] = []
        func check(_ cg: CGEventFlags, _ ns: NSEvent.ModifierFlags) {
            if flags.contains(cg) && !previousFlags.contains(cg) { res.append(ns) }
        }
        check(.maskCommand, .command)
        check(.maskShift, .shift)
        check(.maskControl, .control)
        check(.maskAlternate, .option)
        return res
    }

    private func token(_ key: String, matches mod: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case "command": return mod == .command
        case "shift":   return mod == .shift
        case "control": return mod == .control
        case "option":  return mod == .option
        default:        return false
        }
    }
    private func isModifierToken(_ key: String) -> Bool {
        return ["command", "shift", "control", "option"].contains(key)
    }

    private func modifiersMatch(_ flags: CGEventFlags, required: NSEvent.ModifierFlags) -> Bool {
        var present: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand)   { present.insert(.command) }
        if flags.contains(.maskShift)     { present.insert(.shift) }
        if flags.contains(.maskControl)   { present.insert(.control) }
        if flags.contains(.maskAlternate) { present.insert(.option) }
        let req = required.intersection([.command, .shift, .control, .option])
        return !req.isEmpty && present == req
    }

    // MARK: - 权限
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
    @discardableResult
    static func requestAccessibilityPermission() -> Bool { hasAccessibilityPermission(prompt: true) }
}
