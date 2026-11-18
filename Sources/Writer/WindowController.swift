import AppKit
import WriterCore

final class WindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let libraryToggle = NSToolbarItem.Identifier("library")
    static let previewToggle = NSToolbarItem.Identifier("preview")
    static let titleItem = NSToolbarItem.Identifier("title")

    let split = NSSplitViewController()
    let library = LibraryViewController()
    let editor = EditorViewController()
    let preview = PreviewViewController()
    let libraryItem: NSSplitViewItem
    let editorItem: NSSplitViewItem
    let previewItem: NSSplitViewItem
    let titleField = TitleField()

    private(set) var documentURL: URL?
    private var dirty = false
    private var lastModified: Date?
    private var saveTimer: Timer?
    private var previewTimer: Timer?
    private var quickSearch: QuickSearchController?
    private var versionBrowser: VersionBrowser?
    private var versionedAt: Date?
    private var topHidden = false
    private var bottomHidden = false

    var onClose: ((WindowController) -> Void)?

    init() {
        libraryItem = NSSplitViewItem(sidebarWithViewController: library)
        editorItem = NSSplitViewItem(viewController: editor)
        previewItem = NSSplitViewItem(viewController: preview)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        applyBackground()
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "writer"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self

        libraryItem.minimumThickness = 200
        libraryItem.maximumThickness = 380
        libraryItem.isCollapsed = !Settings.shared.showLibrary
        editorItem.minimumThickness = 320
        editorItem.canCollapse = true
        editorItem.holdingPriority = previewItem.holdingPriority + 1
        previewItem.minimumThickness = 280
        previewItem.canCollapse = true
        split.addSplitViewItem(libraryItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        applyLayout(animated: false)
        window.contentViewController = split
        if !window.setFrameUsingName("WriterMainWindow") {
            window.setContentSize(NSSize(width: 1180, height: 780))
            window.center()
        }
        window.setFrameAutosaveName("WriterMainWindow")

        let toolbar = NSToolbar(identifier: "WriterToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifier = Self.titleItem
        window.toolbar = toolbar
        split.view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))

        editor.onChange = { [weak self] in self?.documentChanged() }
        editor.onOpenLink = { [weak self] in self?.follow($0) }
        preview.onOpenWikilink = { [weak self] in self?.openWikilink($0) }
        library.onOpen = { [weak self] url in
            if url != self?.documentURL { self?.open(url) }
        }
        library.onRenamed = { [weak self] old, new in self?.renamed(from: old, to: new) }
        library.onDeleted = { [weak self] url in self?.deleted(url) }
        library.onJump = { [weak self] location in self?.editor.jump(to: location) }
        titleField.onRename = { [weak self] name in self?.renameCurrent(to: name) ?? false }
        titleField.onFinish = { [weak self] in self?.window?.makeFirstResponder(self?.editor.textView) }

        _ = preview.view
        setChromeHidden(true)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.changed, object: nil)
        center.addObserver(self, selector: #selector(editorScrolled), name: NSView.boundsDidChangeNotification, object: editor.scrollView.contentView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func open(_ url: URL) {
        saveIfNeeded()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            NSSound.beep()
            return
        }
        let (body, authors) = Annotations.split(raw)
        documentURL = url
        editor.documentURL = url
        editor.load(text: body, authors: authors)
        lastModified = modificationDate(url)
        versionedAt = nil
        dirty = false
        refreshOutline()
        updateTitle()
        window?.representedURL = url
        window?.isDocumentEdited = false
        Settings.shared.lastDocument = url.path
        library.select(url)
        refreshPreview()
        window?.makeFirstResponder(editor.textView)
        editor.updateCaret()
    }

    func openInitialDocument() {
        let manager = FileManager.default
        let root = Settings.shared.libraryURL
        if !manager.fileExists(atPath: root.path) {
            try? manager.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["Welcome.md", "Shortcuts.md"] {
                if let source = Bundle.main.resourceURL?.appendingPathComponent(name) {
                    try? manager.copyItem(at: source, to: root.appendingPathComponent(name))
                }
            }
            library.reload()
        }
        if let last = Settings.shared.lastDocument, manager.fileExists(atPath: last) {
            open(URL(fileURLWithPath: last))
        } else if let first = library.files.first(where: { $0.title == "Welcome" }) ?? library.files.first {
            open(first.url)
        } else if let url = library.createFile(in: root) {
            open(url)
        }
    }

    func documentChanged() {
        if NSApp.currentEvent?.type == .keyDown { setChromeHidden(true) }
        dirty = true
        window?.isDocumentEdited = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.saveIfNeeded() }
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.refreshPreview()
            self?.refreshOutline()
        }
    }

    func refreshOutline() {
        library.setOutline(SyntaxScanner.outline(editor.storage.string as NSString))
    }

    func saveVersion(of url: URL) {
        versionedAt = Date()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        guard size > 0, VersionBrowser.versions(of: url).first?.modificationDate != modificationDate(url) else { return }
        _ = try? NSFileVersion.addOfItem(at: url, withContentsOf: url, options: [])
    }

    func saveIfNeeded() {
        saveTimer?.invalidate()
        guard dirty, let url = documentURL else { return }
        if versionedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true { saveVersion(of: url) }
        let file = Annotations.join(body: editor.storage.string, ranges: editor.authorRanges)
        guard (try? file.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        lastModified = modificationDate(url)
        dirty = false
        window?.isDocumentEdited = false
        if url == Settings.customPatternsURL { editor.rebuildChecker() }
    }

    func appActivated() {
        library.reload()
        guard !dirty, let url = documentURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            deleted(url)
        } else if let modified = modificationDate(url), modified != lastModified {
            open(url)
        }
    }

    func renamed(from old: URL, to new: URL) {
        guard let current = documentURL else { return }
        if current == old {
            documentURL = new
        } else if current.path.hasPrefix(old.path + "/") {
            documentURL = URL(fileURLWithPath: new.path + current.path.dropFirst(old.path.count))
        } else {
            return
        }
        editor.documentURL = documentURL
        updateTitle()
        window?.representedURL = documentURL
        Settings.shared.lastDocument = documentURL!.path
        library.select(documentURL)
    }

    func updateTitle() {
        let title = documentURL?.deletingPathExtension().lastPathComponent ?? ""
        window?.title = title
        titleField.stringValue = title
    }

    func renameCurrent(to name: String) -> Bool {
        saveIfNeeded()
        guard let url = documentURL else { return false }
        return library.rename(url, to: name)
    }

    func deleted(_ url: URL) {
        guard let current = documentURL, current == url || current.path.hasPrefix(url.path + "/") else { return }
        dirty = false
        documentURL = nil
        if let next = library.files.first {
            open(next.url)
        } else if let created = library.createFile(in: Settings.shared.libraryURL) {
            open(created)
        }
    }

    func openWikilink(_ name: String) {
        if let node = library.index.find(named: name, in: library.root) {
            open(node.url)
        } else if let url = library.createFile(
            named: name.replacingOccurrences(of: "/", with: "-"),
            in: documentURL?.deletingLastPathComponent() ?? Settings.shared.libraryURL,
            contents: "# \(name)\n\n") {
            open(url)
        }
    }

    func follow(_ target: String) {
        if target.hasPrefix("wiki:") {
            openWikilink(String(target.dropFirst(5)))
        } else if let url = URL(string: target), ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        } else if let base = documentURL?.deletingLastPathComponent() {
            let file = base.appendingPathComponent(target.removingPercentEncoding ?? target).standardizedFileURL
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            if LibraryIndex.textExtensions.contains(file.pathExtension.lowercased()) { open(file) } else { NSWorkspace.shared.open(file) }
        }
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

    func loadBlock(_ path: String) -> ContentBlock? {
        let manager = FileManager.default
        var candidates: [URL] = []
        for base in [documentURL?.deletingLastPathComponent(), Settings.shared.libraryURL, URL(fileURLWithPath: "/")].compactMap({ $0 }) {
            candidates.append(base.appendingPathComponent(path))
            candidates.append(base.appendingPathComponent(path + ".md"))
        }
        var isDirectory: ObjCBool = false
        guard let url = candidates.first(where: { manager.fileExists(atPath: $0.path, isDirectory: &isDirectory) && !isDirectory.boolValue }),
              url.standardizedFileURL != documentURL?.standardizedFileURL else { return nil }
        let kind = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(kind) { return .image(source: PreviewViewController.fileHref(url)) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size < 1_000_000, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if LibraryIndex.textExtensions.contains(kind) { return .markdown(Annotations.split(text).body) }
        if kind == "csv" || kind == "tsv" { return .csv(text) }
        return .code(text.trimmingCharacters(in: .newlines), language: kind)
    }

    func renderHTML() -> String {
        var options = RenderOptions()
        options.hardBreaks = Settings.shared.hardBreaks
        options.smartPunctuation = Settings.shared.smartPunctuation
        options.loadBlock = { [weak self] in self?.loadBlock($0) }
        return MarkdownRenderer.html(editor.storage.string, options: options)
    }

    func refreshPreview(force: Bool = false, completion: ((Int) -> Void)? = nil) {
        guard force || !previewItem.isCollapsed else { return }
        preview.update(html: renderHTML(), documentURL: documentURL, completion: completion)
    }

    @objc func editorScrolled() {
        guard !previewItem.isCollapsed, Settings.shared.syncPreviewScroll else { return }
        let clip = editor.scrollView.contentView
        let range = editor.textView.frame.height - clip.bounds.height
        preview.scroll(to: range > 0 ? min(max(clip.bounds.origin.y / range, 0), 1) : 0)
    }

    @objc func settingsChanged(_ notification: Notification) {
        switch notification.object as? String {
        case "appearance": DispatchQueue.main.async { [weak self] in self?.applyBackground() }
        case "showLibrary": libraryItem.animator().isCollapsed = !Settings.shared.showLibrary
        case "showPreview", "fullPreview":
            applyLayout(animated: true)
            refreshPreview(force: true)
        case "template", "hardBreaks", "smartPunctuation": refreshPreview()
        case "sort", "sortReversed", "smartFolders", "showSmartFolders", "showHashtags", "libraryPath", "libraryFolders": library.reload()
        default: break
        }
    }

    func applyBackground() {
        guard let window else { return }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor = NSColor(cgColor: Theme.background.cgColor) ?? Theme.background
        }
        window.contentView?.needsDisplay = true
    }

    func applyLayout(animated: Bool) {
        let settings = Settings.shared
        let full = settings.showPreview && settings.fullPreview
        let switching = editorItem.isCollapsed != full
        for (item, collapsed) in [(previewItem, !settings.showPreview), (editorItem, full)] where item.isCollapsed != collapsed {
            if animated && !switching { item.animator().isCollapsed = collapsed } else { item.isCollapsed = collapsed }
        }
        if switching {
            split.splitView.layoutSubtreeIfNeeded()
            if settings.showPreview { preview.hideUntilRedrawn() }
        }
        guard let window, window.isVisible else { return }
        if full, window.firstResponder === editor.textView {
            window.makeFirstResponder(preview.webView)
        } else if !full, !(window.firstResponder is NSTextView) {
            window.makeFirstResponder(editor.textView)
        }
    }

    var topChrome: NSView? { window?.standardWindowButton(.closeButton)?.superview }

    func setChromeHidden(top: Bool, bottom: Bool) {
        guard top != topHidden || bottom != bottomHidden else { return }
        topHidden = top
        bottomHidden = bottom
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            topChrome?.animator().alphaValue = top ? 0 : 1
            editor.formatBar.animator().alphaValue = bottom ? 0 : 1
        }
    }

    func setChromeHidden(_ hidden: Bool) { setChromeHidden(top: hidden, bottom: hidden) }

    override func mouseMoved(with event: NSEvent) {
        let bounds = split.view.bounds
        let point = split.view.convert(event.locationInWindow, from: nil)
        let editingTitle = titleField.currentEditor() != nil
        setChromeHidden(top: point.y <= bounds.height - 60 && !editingTitle, bottom: point.y >= 80)
    }

    override func mouseExited(with event: NSEvent) {
        if titleField.currentEditor() == nil { setChromeHidden(true) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.libraryToggle, .sidebarTrackingSeparator, .flexibleSpace, Self.titleItem, .flexibleSpace, Self.previewToggle]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.titleItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Title"
            item.view = titleField
            item.visibilityPriority = .high
            return item
        }
        let (title, symbol, action) = identifier == Self.libraryToggle
            ? ("Library", "sidebar.left", #selector(AppDelegate.toggleLibrary(_:)))
            : ("Preview", "eye", #selector(AppDelegate.togglePreview(_:)))
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.toolTip = "Show or Hide \(title)"
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.action = action
        return item
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        proposedOptions.union(.autoHideToolbar)
    }

    func windowWillClose(_ notification: Notification) {
        saveIfNeeded()
        onClose?(self)
    }

    func windowDidResignKey(_ notification: Notification) { saveIfNeeded() }

    @objc func newDocument(_ sender: Any?) {
        if let url = library.createFile() { open(url) }
    }

    @objc func newFolder(_ sender: Any?) { library.createFolder() }

    @objc func saveDocument(_ sender: Any?) {
        dirty = dirty || documentURL != nil
        saveIfNeeded()
        if let url = documentURL { saveVersion(of: url) }
    }

    @objc func browseVersions(_ sender: Any?) {
        saveIfNeeded()
        guard let url = documentURL, let window else { return }
        guard !VersionBrowser.versions(of: url).isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No earlier versions of “\(url.deletingPathExtension().lastPathComponent)” yet"
            alert.informativeText = "A version is saved when you press ⌘S, and every ten minutes while you write."
            alert.beginSheetModal(for: window)
            return
        }
        let browser = VersionBrowser(url: url, current: editor.storage.string, onRestore: { [weak self] version in
            self?.restore(version, of: url)
        }, onFinish: { [weak self] in
            self?.versionBrowser = nil
        })
        versionBrowser = browser
        browser.present(on: window)
    }

    func restore(_ version: NSFileVersion, of url: URL) {
        guard let text = try? String(contentsOf: version.url, encoding: .utf8) else {
            NSSound.beep()
            return
        }
        saveVersion(of: url)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            NSSound.beep()
            return
        }
        open(url)
    }

    @objc func renameDocument(_ sender: Any?) {
        saveIfNeeded()
        guard let url = documentURL else { return }
        if titleField.window == window {
            setChromeHidden(false)
            titleField.beginEditing()
        } else {
            library.rename(url)
        }
    }

    @objc func revealDocument(_ sender: Any?) {
        if let url = documentURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func trashDocument(_ sender: Any?) {
        guard let url = documentURL else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        dirty = false
        library.trash(url)
    }

    @objc func searchLibrary(_ sender: Any?) {
        Settings.shared.showLibrary = true
        library.focusSearch()
    }

    @objc func showQuickSearch(_ sender: Any?) {
        guard let window else { return }
        let controller = QuickSearchController(library: library) { [weak self] choice in
            self?.quickSearch = nil
            switch choice {
            case .open(let url): self?.open(url)
            case .create(let name): self?.openWikilink(name)
            case .none: break
            }
        }
        quickSearch = controller
        controller.present(on: window)
    }

    @objc func newSmartFolder(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "New Smart Folder"
        alert.informativeText = "Documents that contain every word are listed. Use #tag to match a hashtag."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let name = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        name.placeholderString = "Name"
        let query = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        query.placeholderString = "Search terms"
        query.stringValue = library.searchField.stringValue
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        stack.addSubview(name)
        stack.addSubview(query)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = name.stringValue.trimmingCharacters(in: .whitespaces)
        let terms = query.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !terms.isEmpty else { return }
        Settings.shared.smartFolders = Settings.shared.smartFolders.filter { $0["name"] != title } + [["name": title, "query": terms]]
    }

    override func newWindowForTab(_ sender: Any?) {
        guard let window, let delegate = NSApp.delegate as? AppDelegate else { return }
        let controller = delegate.makeController()
        window.addTabbedWindow(controller.window!, ordered: .above)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openInitialDocument()
    }
}
