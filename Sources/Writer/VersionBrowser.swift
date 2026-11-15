import AppKit
import WriterCore

final class VersionBrowser: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let sheet: NSWindow
    private let table = NSTableView()
    private let textView: NSTextView
    private let restoreButton = NSButton(title: "Restore This Version", target: nil, action: nil)
    private let current: String
    private let versions: [NSFileVersion]
    private let onRestore: (NSFileVersion) -> Void
    private let onFinish: () -> Void
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func versions(of url: URL) -> [NSFileVersion] {
        (NSFileVersion.otherVersionsOfItem(at: url) ?? [])
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    init(url: URL, current: String, onRestore: @escaping (NSFileVersion) -> Void, onFinish: @escaping () -> Void) {
        self.current = current
        self.versions = Self.versions(of: url)
        self.onRestore = onRestore
        self.onFinish = onFinish
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        sheet.minSize = NSSize(width: 560, height: 360)
        let textScroll = NSTextView.scrollableTextView()
        textView = textScroll.documentView as! NSTextView
        super.init()

        textView.isEditable = false
        textView.font = Theme.font()
        textView.textColor = Theme.text
        textView.backgroundColor = Theme.background
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("version"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false

        restoreButton.target = self
        restoreButton.action = #selector(restore)
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [restoreButton, done])
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        [tableScroll, textScroll, buttons].forEach(content.addSubview)
        NSLayoutConstraint.activate([
            tableScroll.topAnchor.constraint(equalTo: content.topAnchor),
            tableScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tableScroll.widthAnchor.constraint(equalToConstant: 220),
            tableScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            textScroll.topAnchor.constraint(equalTo: content.topAnchor),
            textScroll.leadingAnchor.constraint(equalTo: tableScroll.trailingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            textScroll.bottomAnchor.constraint(equalTo: tableScroll.bottomAnchor),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        sheet.contentView = content
        table.reloadData()
        table.selectRowIndexes([versions.isEmpty ? 0 : 1], byExtendingSelection: false)
    }

    func present(on window: NSWindow) {
        window.beginSheet(sheet)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { versions.count + 1 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: row == 0 ? "Current Version" : versions[row - 1].modificationDate.map(formatter.string(from:)) ?? "Unknown Date")
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        let text = row <= 0 ? current : (try? String(contentsOf: versions[row - 1].url, encoding: .utf8)) ?? ""
        textView.string = Annotations.split(text).body
        textView.scroll(.zero)
        restoreButton.isEnabled = row > 0
    }

    @objc func restore() {
        let row = table.selectedRow
        guard row > 0 else { return }
        let version = versions[row - 1]
        finish()
        onRestore(version)
    }

    @objc func finish() {
        sheet.sheetParent?.endSheet(sheet)
        onFinish()
    }
}
