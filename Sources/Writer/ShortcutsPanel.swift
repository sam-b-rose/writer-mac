import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ShortcutsWindow: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
}

final class ShortcutsPanel: NSWindowController {
    static let shared = ShortcutsPanel()

    struct Section {
        let title: String
        let rows: [(title: String, keys: String)]
    }

    static let columnWidth: CGFloat = 268
    static let columnGap: CGFloat = 48
    static let inset = NSEdgeInsets(top: 52, left: 36, bottom: 36, right: 36)
    static let skippedMenus: Set<String> = ["Window", "Help"]
    static let skippedTitles: Set<String> = ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All", "Emoji & Symbols", "Show Completions"]
    static let prefixedParents: Set<String> = ["Paste As", "Mark As"]
    static let editorRows: [(String, String)] = [
        ("Follow Link or Wikilink", "⌘ Click"),
        ("Next Table Cell", "⇥"),
        ("Previous Table Cell", "⇧⇥"),
        ("Indent List Item", "⇥"),
        ("Outdent List Item", "⇧⇥"),
        ("Close This Panel", "⎋"),
    ]

    private let scrollView = NSScrollView()
    private let content = FlippedView()

    private init() {
        let panel = ShortcutsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Keyboard Shortcuts"
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Theme.background
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)

        scrollView.documentView = content
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        panel.contentView = scrollView
    }

    required init?(coder: NSCoder) { fatalError() }

    static func keys(for item: NSMenuItem) -> String {
        let names: [String: String] = ["\r": "↩", "\u{8}": "⌫", "\u{7f}": "⌫", "\u{1b}": "⎋", " ": "Space", "\t": "⇥"]
        let flags = item.keyEquivalentModifierMask
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out + (names[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
    }

    static func label(_ item: NSMenuItem, parent: String?) -> String {
        let title = item.title.replacingOccurrences(of: "…", with: "")
        guard let parent, prefixedParents.contains(parent) else { return title }
        return "\(parent) \(title)"
    }

    static func rows(in menu: NSMenu, parent: String? = nil) -> [(title: String, keys: String)] {
        menu.items.flatMap { item -> [(title: String, keys: String)] in
            if let submenu = item.submenu { return rows(in: submenu, parent: item.title) }
            guard !item.keyEquivalent.isEmpty, !item.isHidden, !item.isAlternate, !skippedTitles.contains(item.title) else { return [] }
            return [(label(item, parent: parent), keys(for: item))]
        }
    }

    static func collapseHeadings(_ rows: [(title: String, keys: String)]) -> [(title: String, keys: String)] {
        let headings = rows.filter { $0.title.hasPrefix("Heading ") && Int($0.title.dropFirst(8)) != nil }
        guard headings.count > 2, let first = headings.first, let last = headings.last,
              let index = rows.firstIndex(where: { $0.title == first.title }) else { return rows }
        var out = rows.filter { row in !headings.contains { $0.title == row.title } }
        out.insert(("Heading \(first.title.dropFirst(8))–\(last.title.dropFirst(8))", "\(first.keys) – \(last.keys)"), at: index)
        return out
    }

    static func sections() -> [Section] {
        let menus = (NSApp.mainMenu?.items.dropFirst() ?? []).compactMap { top -> Section? in
            guard !skippedMenus.contains(top.title), let submenu = top.submenu else { return nil }
            let rows = collapseHeadings(rows(in: submenu))
            return rows.isEmpty ? nil : Section(title: top.title, rows: rows)
        }
        return menus + [Section(title: "Editor", rows: editorRows)]
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, kern: CGFloat = 0) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: kern,
        ])
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func sectionView(_ section: Section) -> NSView {
        let header = text(section.title.uppercased(), size: 10.5, weight: .semibold, color: Theme.muted, kern: 0.8)
        let rows = section.rows.map { row -> NSView in
            let title = text(row.title, size: 13, color: NSColor.labelColor)
            let isWord = row.keys.range(of: "\\p{L}{2,}", options: .regularExpression) != nil
            let keys = text(row.keys, size: 13, color: NSColor.secondaryLabelColor, kern: isWord ? 0 : 1.5)
            keys.setContentCompressionResistancePriority(.required, for: .horizontal)
            keys.alignment = .right
            let line = NSStackView(views: [title, keys])
            line.orientation = .horizontal
            line.distribution = .fill
            line.spacing = 12
            line.translatesAutoresizingMaskIntoConstraints = false
            return line
        }
        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.distribution = .fill
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setCustomSpacing(12, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func columnView(_ sections: [Section]) -> NSStackView {
        let column = NSStackView(views: sections.map(sectionView))
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 30
        column.distribution = .fill
        column.setHuggingPriority(.required, for: .vertical)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
        for view in column.arrangedSubviews { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        return column
    }

    func prepare() {
        var columns: [[Section]] = [[], []]
        var heights = [0, 0]
        for section in Self.sections() {
            let target = heights[0] <= heights[1] ? 0 : 1
            columns[target].append(section)
            heights[target] += section.rows.count + 3
        }

        let title = text("Keyboard Shortcuts", size: 17, weight: .semibold, color: NSColor.labelColor)
        let row = NSStackView(views: columns.map(columnView))
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = Self.columnGap
        row.translatesAutoresizingMaskIntoConstraints = false

        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(title)
        content.addSubview(row)
        let inset = Self.inset
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: inset.top),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset.left),
            row.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset.left),
        ])

        let width = inset.left + inset.right + Self.columnWidth * 2 + Self.columnGap
        content.frame.size.width = width
        content.layoutSubtreeIfNeeded()
        let height = ceil(row.frame.maxY + inset.bottom)
        content.frame.size.height = height

        guard let window else { return }
        window.backgroundColor = Theme.background
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let size = NSSize(width: width, height: min(height, available * 0.85))
        window.setFrame(NSRect(origin: window.frame.origin, size: window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size), display: false)
        scrollView.contentView.scroll(to: .zero)
    }

    func toggle(over parent: NSWindow?) {
        guard let window else { return }
        if window.isVisible {
            close()
            return
        }
        prepare()
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
