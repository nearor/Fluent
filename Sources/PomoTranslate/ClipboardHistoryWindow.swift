import Cocoa

/// @user_flow 剪贴板历史面板
/// 顶部搜索（仅文本）；中部列表（每行右侧有 ✕ 删除按钮）；底部预览区（文本看全文 / 图片看大图）。
/// ↑↓ 选择；回车或双击确认粘贴；Esc 关闭。
final class ClipboardHistoryWindowController: NSWindowController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    var onSelect: ((ClipItem) -> Void)?
    var onDelete: ((ClipItem) -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let previewText = NSTextView()
    private let previewScroll = NSScrollView()
    private let previewImage = NSImageView()
    private var all: [ClipItem] = []
    private var filtered: [ClipItem] = []

    convenience init() {
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "剪贴板历史"
        win.isFloatingPanel = true
        win.hidesOnDeactivate = false
        win.center()
        self.init(window: win)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        searchField.frame = NSRect(x: 12, y: 484, width: 356, height: 26)
        searchField.placeholderString = "搜索文本历史…"
        searchField.delegate = self
        searchField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(searchField)

        // 列表
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 168, width: 356, height: 308))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = 336
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 40
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(confirmSelection)
        scroll.documentView = tableView
        content.addSubview(scroll)

        // 预览区标题
        let pl = NSTextField(labelWithString: "预览")
        pl.font = NSFont.systemFont(ofSize: 11); pl.textColor = .secondaryLabelColor
        pl.frame = NSRect(x: 12, y: 150, width: 100, height: 14)
        pl.autoresizingMask = [.maxYMargin]
        content.addSubview(pl)

        // 预览：文本
        previewScroll.frame = NSRect(x: 12, y: 12, width: 356, height: 134)
        previewScroll.autoresizingMask = [.width]
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewText.isEditable = false
        previewText.font = NSFont.systemFont(ofSize: 12)
        previewText.textContainerInset = NSSize(width: 6, height: 6)
        previewScroll.documentView = previewText
        content.addSubview(previewScroll)

        // 预览：图片
        previewImage.frame = NSRect(x: 12, y: 12, width: 356, height: 134)
        previewImage.autoresizingMask = [.width]
        previewImage.imageScaling = .scaleProportionallyDown
        previewImage.imageAlignment = .alignCenter
        previewImage.isHidden = true
        content.addSubview(previewImage)
    }

    func present(items: [ClipItem]) {
        all = items
        searchField.stringValue = ""
        applyFilter("")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
        if !filtered.isEmpty { selectRow(0) }
    }

    private func applyFilter(_ q: String) {
        let key = q.trimmingCharacters(in: .whitespaces).lowercased()
        filtered = key.isEmpty ? all : all.filter { ($0.searchText?.lowercased().contains(key)) ?? false }
        tableView.reloadData()
        if !filtered.isEmpty { selectRow(0) } else { updatePreview(nil) }
    }

    private func selectRow(_ i: Int) {
        guard i >= 0, i < filtered.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        tableView.scrollRowToVisible(i)
        updatePreview(filtered[i])
    }

    private func updatePreview(_ item: ClipItem?) {
        guard let item else {
            previewText.string = ""; previewImage.image = nil
            previewScroll.isHidden = false; previewImage.isHidden = true
            return
        }
        switch item {
        case .text(let s):
            previewText.string = s
            previewScroll.isHidden = false; previewImage.isHidden = true
        case .image(let data, _, _, _):
            previewImage.image = NSImage(data: data)
            previewScroll.isHidden = true; previewImage.isHidden = false
        }
    }

    // MARK: - 数据源
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 38))

        // 删除按钮（右侧）
        let del = NSButton(title: "✕", target: self, action: #selector(deleteRow(_:)))
        del.isBordered = false
        del.font = NSFont.systemFont(ofSize: 12)
        del.frame = NSRect(x: 312, y: 9, width: 22, height: 20)
        del.toolTip = "删除这条"
        container.addSubview(del)

        let text = NSTextField(labelWithString: item.preview)
        text.lineBreakMode = .byTruncatingTail
        text.font = NSFont.systemFont(ofSize: 12)

        if case .image(_, _, let thumb, _) = item {
            let w = min(thumb.size.width, 90)
            let iv = NSImageView(frame: NSRect(x: 2, y: 2, width: w, height: 34))
            iv.image = thumb
            iv.imageScaling = .scaleProportionallyDown
            container.addSubview(iv)
            text.frame = NSRect(x: w + 8, y: 9, width: 306 - w - 8, height: 20)
        } else {
            text.frame = NSRect(x: 6, y: 9, width: 300, height: 20)
        }
        container.addSubview(text)
        return container
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let r = tableView.selectedRow
        updatePreview(r >= 0 && r < filtered.count ? filtered[r] : nil)
    }

    // MARK: - 动作
    @objc private func confirmSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row]
        window?.orderOut(nil)
        onSelect?(item)
    }

    @objc private func deleteRow(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row]
        onDelete?(item)
        all.removeAll { ClipboardHistory.same($0, item) }
        applyFilter(searchField.stringValue)
    }

    // MARK: - 键盘导航
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selectRow(min(tableView.selectedRow + 1, filtered.count - 1)); return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(max(tableView.selectedRow - 1, 0)); return true
        case #selector(NSResponder.insertNewline(_:)):
            confirmSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.orderOut(nil); return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }
}
