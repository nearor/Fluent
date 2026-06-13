import Cocoa
import ApplicationServices

/// @user_flow 翻译反馈 HUD
/// 小巧的胶囊提示，跟随鼠标附近显示，不抢焦点、不挡操作。
/// 加载时显示旋转菊花 + 文案；完成/失败短暂显示后淡出。
final class HUDOverlay {
    static let shared = HUDOverlay()

    private var panel: NSPanel?
    private var blur: NSVisualEffectView!
    private let spinner = NSProgressIndicator()
    private let iconLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    /// 本次翻译捕获的光标锚点（Cocoa 坐标）。loading 时捕获，结果复用，hide 后清空。
    private var anchor: NSRect?

    private let height: CGFloat = 38
    private let hPadding: CGFloat = 14
    private let gap: CGFloat = 7
    private let spinnerSize: CGFloat = 16

    private func ensurePanel() {
        guard panel == nil else { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 强制深色外观：深底白字，不受系统亮/暗模式影响
        p.appearance = NSAppearance(named: .darkAqua)

        let bg = NSVisualEffectView(frame: p.contentView!.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = height / 2      // 全圆角胶囊
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        p.contentView?.addSubview(bg)
        blur = bg

        // 旋转菊花
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        bg.addSubview(spinner)

        // 结果图标（✓ / ✗）
        iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        iconLabel.alignment = .center
        iconLabel.backgroundColor = .clear
        iconLabel.isBezeled = false
        iconLabel.isEditable = false
        bg.addSubview(iconLabel)

        // 文案
        textLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textLabel.textColor = .white
        textLabel.backgroundColor = .clear
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        bg.addSubview(textLabel)

        panel = p
    }

    /// 根据内容重新布局并定位到鼠标附近。
    private func layoutAndPlace(showSpinner: Bool, icon: String, iconColor: NSColor?, text: String) {
        guard let p = panel else { return }

        // 左侧元素宽度（菊花或图标）
        let leadW: CGFloat = showSpinner ? spinnerSize : (icon.isEmpty ? 0 : 18)

        textLabel.stringValue = text
        textLabel.sizeToFit()
        let textW = min(textLabel.frame.width, 320)

        let hasLead = leadW > 0
        let contentW = leadW + (hasLead ? gap : 0) + textW
        let totalW = hPadding * 2 + contentW

        p.setContentSize(NSSize(width: totalW, height: height))

        let midY = height / 2
        var x = hPadding

        if showSpinner {
            spinner.isHidden = false
            iconLabel.isHidden = true
            spinner.frame = NSRect(x: x, y: midY - spinnerSize / 2, width: spinnerSize, height: spinnerSize)
            spinner.startAnimation(nil)
            x += spinnerSize + gap
        } else if !icon.isEmpty {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            iconLabel.isHidden = false
            iconLabel.stringValue = icon
            iconLabel.textColor = iconColor ?? .white
            iconLabel.frame = NSRect(x: x, y: midY - 10, width: 18, height: 20)
            x += 18 + gap
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            iconLabel.isHidden = true
        }

        textLabel.frame = NSRect(x: x, y: midY - textLabel.frame.height / 2, width: textW, height: textLabel.frame.height)

        // 定位优先级：光标右侧（贴在刚打完的文字最后面）→ 焦点窗口底部 → 鼠标上方
        var originX: CGFloat
        var originY: CGFloat
        let gapX: CGFloat = 10

        if let a = anchor {
            originX = a.maxX + gapX          // 光标右侧，不盖文字
            originY = a.midY - height / 2
        } else if let wf = focusedWindowFrameCocoa() {
            originX = wf.midX - totalW / 2
            originY = wf.minY + 70
        } else {
            let mouse = NSEvent.mouseLocation
            originX = mouse.x - totalW / 2
            originY = mouse.y + 26
        }

        let probe = NSPoint(x: originX + totalW / 2, y: originY + height / 2)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(probe) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        if let f = screen?.frame {
            // 光标锚点时若右边放不下，挪到光标下方、左对齐光标，仍不盖住文字
            if let a = anchor, originX + totalW > f.maxX - 8 {
                originX = min(a.minX, f.maxX - totalW - 8)
                originY = a.minY - height - 6
            }
            originX = max(f.minX + 8, min(originX, f.maxX - totalW - 8))
            originY = max(f.minY + 8, min(originY, f.maxY - height - 8))
        }
        p.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    /// 取当前聚焦输入框的光标屏幕位置（转 Cocoa 坐标）。取不到返回 nil。
    private func caretAnchorCocoa() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        let el = f as! AXUIElement

        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rr = rangeRef, CFGetTypeID(rr) == AXValueGetTypeID() else { return nil }
        var sel = CFRange()
        AXValueGetValue(rr as! AXValue, .cfRange, &sel)

        let caretLoc = sel.location + sel.length
        // 先试零长范围（插入点本身）
        if let rect = boundsForRange(el, location: caretLoc, length: 0), rect.height > 0 {
            return toCocoa(rect)
        }
        // 退一步：取末字符范围，锚到它的右边缘
        if caretLoc > 0, let rect = boundsForRange(el, location: caretLoc - 1, length: 1), rect.height > 0 {
            return toCocoa(CGRect(x: rect.maxX, y: rect.origin.y, width: 0, height: rect.height))
        }
        return nil
    }

    private func boundsForRange(_ el: AXUIElement, location: Int, length: Int) -> CGRect? {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
                el, kAXBoundsForRangeParameterizedAttribute as CFString, value, &boundsRef) == .success,
              let br = boundsRef, CFGetTypeID(br) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(br as! AXValue, .cgRect, &rect)
        return rect
    }

    /// AX 全局坐标（主屏左上角原点、y 向下）转 Cocoa（左下角原点、y 向上）。
    private func toCocoa(_ rect: CGRect) -> NSRect {
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let y = screenH - (rect.origin.y + rect.height)
        return NSRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    /// 取当前最前 app 的焦点窗口位置（转换为 Cocoa 左下角坐标系）。取不到返回 nil。
    private func focusedWindowFrameCocoa() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var winRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let w = winRef, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        let win = w as! AXUIElement

        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }

        // AX 是全局左上角原点（翻转），转成 Cocoa 左下角原点
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let cocoaY = screenH - (pos.y + size.height)
        return NSRect(x: pos.x, y: cocoaY, width: size.width, height: size.height)
    }

    /// 加载中（旋转菊花），持续到 showResult / hide。
    func showLoading(_ text: String = "翻译中…") {
        DispatchQueue.main.async {
            self.ensurePanel()
            self.hideWorkItem?.cancel()
            self.anchor = self.caretAnchorCocoa()        // 捕获光标位置，定位到文字末尾
            self.layoutAndPlace(showSpinner: true, icon: "", iconColor: nil, text: text)
            guard let p = self.panel else { return }
            p.alphaValue = 1
            p.orderFrontRegardless()
        }
    }

    /// 显示结果，短暂停留后淡出。
    func showResult(success: Bool, text: String, autoHide: TimeInterval = 1.6) {
        DispatchQueue.main.async {
            self.ensurePanel()
            let icon = success ? "✓" : "✗"
            let color: NSColor = success ? .systemGreen : .systemRed
            // 结果复用 loading 时的光标锚点；若是独立提示（无 loading）则现取一次
            if self.anchor == nil { self.anchor = self.caretAnchorCocoa() }
            self.layoutAndPlace(showSpinner: false, icon: icon, iconColor: color, text: text)
            guard let p = self.panel else { return }
            p.alphaValue = 1
            p.orderFrontRegardless()
            self.scheduleHide(after: autoHide)
        }
    }

    func hide() {
        DispatchQueue.main.async { self.scheduleHide(after: 0) }
    }

    private func scheduleHide(after: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let p = self.panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                p.animator().alphaValue = 0
            } completionHandler: {
                p.orderOut(nil)
                self.spinner.stopAnimation(nil)
                self.anchor = nil       // 本次结束，清空锚点
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }
}
