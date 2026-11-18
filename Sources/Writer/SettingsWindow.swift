import AppKit
import WriterCore

final class ControlHandler: NSObject {
    let action: (NSControl) -> Void

    init(_ action: @escaping (NSControl) -> Void) { self.action = action }

    @objc func fire(_ sender: NSControl) { action(sender) }
}

final class SettingsPane: NSViewController {
    let symbol: String
    var refreshers: [() -> Void] = []
    private var handlers: [ControlHandler] = []
    private var rows: [(String, NSView)] = []

    init(_ title: String, symbol: String) {
        self.symbol = symbol
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let grid = NSGridView(views: rows.map { title, control in
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            return [label, control]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 16
        grid.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 540),
        ])
        view = root
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Settings.changed, object: nil)
    }

    @objc func refresh() { refreshers.forEach { $0() } }

    func row(_ title: String, _ views: NSView...) {
        guard views.count > 1 else {
            rows.append((title, views[0]))
            return
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        rows.append((title, stack))
    }

    func bind(_ control: NSControl, _ action: @escaping (NSControl) -> Void) {
        let handler = ControlHandler(action)
        handlers.append(handler)
        control.target = handler
        control.action = #selector(ControlHandler.fire(_:))
    }

    func checkbox(_ title: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        bind(button) { set(($0 as? NSButton)?.state == .on) }
        refreshers.append { button.state = get() ? .on : .off }
        return button
    }

    func popup<Value: Equatable>(
        _ options: @escaping () -> [(String, Value)], _ get: @escaping () -> Value, _ set: @escaping (Value) -> Void
    ) -> NSPopUpButton {
        let popup = NSPopUpButton()
        bind(popup) { control in
            guard let index = (control as? NSPopUpButton)?.indexOfSelectedItem, options().indices.contains(index) else { return }
            set(options()[index].1)
        }
        refreshers.append {
            let current = options()
            if popup.itemTitles != current.map(\.0) {
                popup.removeAllItems()
                popup.addItems(withTitles: current.map(\.0))
            }
            popup.selectItem(at: current.firstIndex { $0.1 == get() } ?? -1)
        }
        return popup
    }

    func popup<Value: Equatable>(_ options: [(String, Value)], _ get: @escaping () -> Value, _ set: @escaping (Value) -> Void) -> NSPopUpButton {
        popup({ options }, get, set)
    }

    func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        bind(button) { _ in action() }
        return button
    }

    func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 340
        return label
    }

    func horizontal(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.alignment = .firstBaseline
        stack.spacing = 8
        return stack
    }
}

extension SettingsPane {
    static var settings: Settings { .shared }
    static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    static func general() -> SettingsPane {
        let pane = SettingsPane("General", symbol: "gearshape")
        let s = settings
        pane.row("Appearance:", pane.popup([("Match System", "auto"), ("Light", "light"), ("Dark", "dark")], { s.appearance }, { s.appearance = $0 }))
        pane.row(
            "Preview template:",
            pane.popup({ (Settings.builtInTemplates + Settings.customTemplates).map { ($0, $0) } }, { s.template }, { s.template = $0 }),
            pane.button("Open Templates Folder") { NSWorkspace.shared.open(Settings.templatesDirectory) },
            pane.note("Add a .css file to the Templates folder to use it as a custom template."))
        pane.row("Preview:", pane.checkbox("Scroll Preview in sync with Editor", { s.syncPreviewScroll }, { s.syncPreviewScroll = $0 }))
        return pane
    }

    static func editor() -> SettingsPane {
        let pane = SettingsPane("Editor", symbol: "character.cursor.ibeam")
        let s = settings
        pane.row("Typeface:", pane.popup([("Mono", "mono"), ("Duo", "duo"), ("Quattro", "quattro")], { s.font }, { s.font = $0 }))

        let slider = NSSlider(value: s.size, minValue: 11, maxValue: 32, target: nil, action: nil)
        slider.isContinuous = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let sizeLabel = NSTextField(labelWithString: "")
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        pane.bind(slider) { s.size = ($0 as? NSSlider)?.doubleValue.rounded() ?? Settings.defaultSize }
        pane.refreshers.append {
            slider.doubleValue = s.size
            sizeLabel.stringValue = "\(Int(s.size)) pt"
        }
        pane.row("Text size:", pane.horizontal(slider, sizeLabel, pane.button("Default") { s.size = Settings.defaultSize }))

        pane.row("Line length limit:", pane.popup([64, 72, 80].map { ("\($0) characters", $0) }, { s.lineLength }, { s.lineLength = $0 }))
        pane.row("Focus scope:", pane.popup([("Sentence", "sentence"), ("Paragraph", "paragraph")], { s.focusScope }, { s.focusScope = $0 }))
        pane.row("Scrolling:", pane.checkbox("Typewriter mode", { s.typewriter }, { s.typewriter = $0 }))
        pane.row("Writing:", pane.checkbox("One sentence per line", { s.sentenceLines }, { s.sentenceLines = $0 }))
        pane.rowsOfCheckboxes("Syntax:", PartOfSpeech.allCases.map { kind in
            let checkbox = pane.checkbox(kind.title, { s.syntax.contains(kind) }, { on in
                if on { s.syntax.insert(kind) } else { s.syntax.remove(kind) }
            })
            checkbox.attributedTitle = NSAttributedString(
                string: kind.title, attributes: [.foregroundColor: Theme.partsOfSpeech[kind] ?? .labelColor])
            return checkbox
        })
        pane.rowsOfCheckboxes("Style check:", StyleCategory.allCases.map { category in
            pane.checkbox(category.title, { s.style.contains(category) }, { on in
                if on { s.style.insert(category) } else { s.style.remove(category) }
            })
        } + [pane.button("Edit Custom Patterns…") { delegate?.editCustomPatterns(nil) }])
        pane.row(
            "Authors:",
            pane.checkbox("Show authors", { s.showAuthors }, { s.showAuthors = $0 }),
            pane.note("Text from AI, references, and other authors is colored."))
        return pane
    }

    static func typing() -> SettingsPane {
        let pane = SettingsPane("Typing", symbol: "keyboard")
        let s = settings
        pane.row(
            "Spelling and grammar:",
            pane.checkbox("Check spelling while typing", { s.checkSpelling }, { s.checkSpelling = $0 }),
            pane.checkbox("Check grammar with spelling", { s.checkGrammar }, { s.checkGrammar = $0 }),
            pane.checkbox("Correct spelling automatically", { s.correctSpelling }, { s.correctSpelling = $0 }))
        pane.row(
            "Smart substitutions:",
            pane.checkbox("Quotes", { s.smartQuotes }, { s.smartQuotes = $0 }),
            pane.checkbox("Dashes", { s.smartDashes }, { s.smartDashes = $0 }),
            pane.checkbox("Text replacement", { s.textReplacement }, { s.textReplacement = $0 }),
            pane.checkbox("Copy/paste", { s.smartCopyPaste }, { s.smartCopyPaste = $0 }))
        pane.row("Completions:", pane.checkbox("Show inline predictive text", { s.inlinePrediction }, { s.inlinePrediction = $0 }))
        pane.row("Indent using:", pane.popup([("Spaces", false), ("Tabs", true)], { s.indentWithTabs }, { s.indentWithTabs = $0 }))
        let width = pane.popup([2, 4, 8].map { ("\($0) spaces", $0) }, { s.indentWidth }, { s.indentWidth = $0 })
        pane.refreshers.append { width.isEnabled = !s.indentWithTabs }
        pane.row("Indent width:", width, pane.note("Tab indents list items. Shift-Tab outdents them."))
        return pane
    }

    static func library() -> SettingsPane {
        let pane = SettingsPane("Library", symbol: "sidebar.left")
        let s = settings
        pane.row("Sort by:", pane.popup(LibrarySort.allCases.map { ($0.title, $0) }, { s.sort }, { s.sort = $0 }))
        pane.row("Order:", pane.popup({
            s.sort == .name ? [("A to Z", false), ("Z to A", true)] : [("Newest on Top", false), ("Oldest on Top", true)]
        }, { s.sortReversed }, { s.sortReversed = $0 }))
        pane.row(
            "Show:",
            pane.checkbox("Smart Folders", { s.showSmartFolders }, { s.showSmartFolders = $0 }),
            pane.checkbox("Hashtags", { s.showHashtags }, { s.showHashtags = $0 }))
        pane.row(
            "Default extension:",
            pane.popup(["md", "markdown", "txt", "text"].map { (".\($0)", $0) }, { s.defaultExtension }, { s.defaultExtension = $0 }),
            pane.note("New files are created with this extension."))
        return pane
    }

    static func markdown() -> SettingsPane {
        let pane = SettingsPane("Markdown", symbol: "number")
        let s = settings
        pane.row("Bold:", pane.popup([("Double asterisks  **bold**", "**"), ("Double underscores  __bold__", "__")], { s.boldMarker }, { s.boldMarker = $0 }))
        pane.row("Italic:", pane.popup([("Asterisks  *italic*", "*"), ("Underscores  _italic_", "_")], { s.italicMarker }, { s.italicMarker = $0 }))
        pane.row("List bullet:", pane.popup([("Hyphen  -", "-"), ("Asterisk  *", "*"), ("Plus  +", "+")], { s.listBullet }, { s.listBullet = $0 }))
        pane.row("Ordered list:", pane.popup([("Period  1.", "."), ("Parenthesis  1)", ")")], { s.orderedListDelimiter }, { s.orderedListDelimiter = $0 }))
        pane.row(
            "Paragraphs:",
            pane.checkbox("Single return starts a new paragraph", { s.hardBreaks }, { s.hardBreaks = $0 }),
            pane.note("By default, Markdown needs an empty line between paragraphs."))
        pane.row(
            "Typography:",
            pane.checkbox("Apply smart punctuation", { s.smartPunctuation }, { s.smartPunctuation = $0 }),
            pane.note("Converts straight quotes and plain dashes in Preview and exports."))
        return pane
    }

    func rowsOfCheckboxes(_ title: String, _ views: [NSView]) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        row(title, stack)
    }
}

final class SettingsTabViewController: NSTabViewController {
    override func viewDidAppear() {
        super.viewDidAppear()
        fitWindow()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow()
    }

    func fitWindow() {
        let item = tabViewItems.indices.contains(selectedTabViewItemIndex) ? tabViewItems[selectedTabViewItemIndex] : nil
        guard let window = view.window, let content = item?.viewController?.view else { return }
        window.title = item?.label ?? "Settings"
        content.layoutSubtreeIfNeeded()
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        guard frame.size != window.frame.size else { return }
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - frame.height, width: frame.width, height: frame.height), display: true, animate: window.isVisible)
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    init() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for pane in [SettingsPane.general(), .editor(), .typing(), .library(), .markdown()] {
            let item = NSTabViewItem(viewController: pane)
            item.label = pane.title ?? ""
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("WriterSettings")
    }

    required init?(coder: NSCoder) { fatalError() }
}
