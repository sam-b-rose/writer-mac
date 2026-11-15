import AppKit
import WriterCore

final class SidebarItem: NSObject {
    enum Kind: String { case section, folder, file, smartFolder, tag, heading }

    let kind: Kind
    let title: String
    let url: URL?
    var children: [SidebarItem]
    var level = 0
    var location = 0

    init(_ kind: Kind, _ title: String, url: URL? = nil, children: [SidebarItem] = []) {
        self.kind = kind
        self.title = title
        self.url = url
        self.children = children
    }

    convenience init(heading: OutlineHeading) {
        self.init(.heading, heading.title)
        level = heading.level
        location = heading.location
    }

    var key: String { "\(kind.rawValue):\(url?.path ?? title)" }

    var symbol: String? {
        switch kind {
        case .section: return nil
        case .folder: return "folder"
        case .file: return "doc.text"
        case .smartFolder: return "gearshape"
        case .tag: return "number"
        case .heading: return nil
        }
    }

    var isDropTarget: Bool { url != nil && (kind == .folder || kind == .section) }
}

final class HeadingCell: NSTableCellView {
    var indent: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        indent = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
        NSLayoutConstraint.activate([
            indent,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class LibraryViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    let index = LibraryIndex()
    let outline = NSOutlineView()
    let searchField = NSSearchField()

    var onOpen: ((URL) -> Void)?
    var onRenamed: ((URL, URL) -> Void)?
    var onDeleted: ((URL) -> Void)?
    var onJump: ((Int) -> Void)?

    private(set) var root = LibraryNode.placeholder
    private var sections: [SidebarItem] = []
    private var headings: [SidebarItem] = []
    private var expanded: Set<String> = []
    private var collapsedSections: Set<String> = []
    private var selectedURL: URL?
    private var restoring = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        reload()
    }

    var files: [LibraryNode] { index.files(in: root) }

    func item(for node: LibraryNode) -> SidebarItem {
        SidebarItem(node.isFolder ? .folder : .file, node.title, url: node.url, children: node.children.map(item(for:)))
    }

    func fileItems(_ nodes: [LibraryNode]) -> [SidebarItem] {
        nodes.map { SidebarItem(.file, $0.title, url: $0.url) }
    }

    var locations: [URL] {
        let settings = Settings.shared
        return [settings.libraryURL] + settings.libraryFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var isSearching: Bool { !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

    func reload() {
        root = index.scan(locations, sort: Settings.shared.sort, reversed: Settings.shared.sortReversed)
        rebuild()
    }

    func setOutline(_ outlineHeadings: [OutlineHeading]) {
        let unchanged = outlineHeadings.count == headings.count
            && zip(outlineHeadings, headings).allSatisfy { $0.title == $1.title && $0.level == $1.level }
        if unchanged {
            zip(outlineHeadings, headings).forEach { $1.location = $0.location }
            return
        }
        headings = outlineHeadings.map(SidebarItem.init(heading:))
        guard !isSearching else { return }
        if !headings.isEmpty, let section = sections.last, section.title == "Outline", section.url == nil {
            section.children = headings
            restoring = true
            outline.reloadItem(section, reloadChildren: true)
            highlightSelection()
            restoring = false
        } else {
            rebuild()
        }
    }

    private func rebuild() {
        let settings = Settings.shared
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            sections = [SidebarItem(.section, "Results", children: fileItems(index.search(query, in: root)))]
        } else {
            sections = root.children.enumerated().map { offset, location in
                SidebarItem(.section, offset == 0 ? "Library" : location.title, url: location.url, children: location.children.map(item(for:)))
            }
            let smart = !settings.showSmartFolders ? [] : settings.smartFolders.compactMap { folder -> SidebarItem? in
                guard let name = folder["name"], let query = folder["query"] else { return nil }
                return SidebarItem(.smartFolder, name, children: fileItems(index.search(query, in: root)))
            }
            if !smart.isEmpty { sections.append(SidebarItem(.section, "Smart Folders", children: smart)) }
            let tags = !settings.showHashtags ? [] : index.hashtags(in: root).sorted { $0.key < $1.key }.map { tag, nodes in
                SidebarItem(.tag, tag, children: fileItems(nodes.sorted { $0.title < $1.title }))
            }
            if !tags.isEmpty { sections.append(SidebarItem(.section, "Hashtags", children: tags)) }
            if !headings.isEmpty { sections.append(SidebarItem(.section, "Outline", children: headings)) }
        }
        restoring = true
        outline.reloadData()
        func restore(_ items: [SidebarItem]) {
            for item in items where isExpanded(item) {
                outline.expandItem(item)
                restore(item.children)
            }
        }
        restore(sections)
        highlightSelection()
        restoring = false
    }

    func select(_ url: URL?) {
        selectedURL = url
        restoring = true
        highlightSelection()
        restoring = false
    }

    private func highlightSelection() {
        guard let url = selectedURL else {
            outline.deselectAll(nil)
            return
        }
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? SidebarItem, item.kind == .file, item.url == url {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                return
            }
        }
        outline.deselectAll(nil)
    }

    var targetFolder: URL {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        if let item = outline.item(atRow: row) as? SidebarItem, let url = item.url {
            return item.isDropTarget ? url : url.deletingLastPathComponent()
        }
        return selectedURL?.deletingLastPathComponent() ?? Settings.shared.libraryURL
    }

    func uniqueURL(in folder: URL, name: String, pathExtension: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        if !pathExtension.isEmpty { candidate.appendPathExtension(pathExtension) }
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter)")
            if !pathExtension.isEmpty { candidate.appendPathExtension(pathExtension) }
            counter += 1
        }
        return candidate
    }

    @discardableResult
    func createFile(named name: String = "Untitled", in folder: URL? = nil, contents: String = "") -> URL? {
        let folder = folder ?? targetFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueURL(in: folder, name: name, pathExtension: Settings.shared.defaultExtension)
        guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        expand(folder)
        reload()
        return url
    }

    func prompt(_ message: String, value: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let result = field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        return result.isEmpty ? nil : result
    }

    func createFolder() {
        guard let name = prompt("New Folder", value: "New Folder", button: "Create") else { return }
        let parent = targetFolder
        let url = uniqueURL(in: parent, name: name, pathExtension: "")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        expand(parent)
        reload()
    }

    func rename(_ url: URL) {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let current = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        guard let name = prompt("Rename “\(current)”", value: current, button: "Rename"), name != current else { return }
        rename(url, to: name)
    }

    @discardableResult
    func rename(_ url: URL, to name: String) -> Bool {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var target = url.deletingLastPathComponent().appendingPathComponent(name)
        if !isFolder { target.appendPathExtension(url.pathExtension) }
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
              !FileManager.default.fileExists(atPath: target.path),
              (try? FileManager.default.moveItem(at: url, to: target)) != nil else {
            NSSound.beep()
            return false
        }
        onRenamed?(url, target)
        reload()
        return true
    }

    func trash(_ url: URL) {
        guard (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil else {
            NSSound.beep()
            return
        }
        reload()
        onDeleted?(url)
    }

    @objc func searchChanged() { reload() }

    func focusSearch() { view.window?.makeFirstResponder(searchField) }

    var clickedItem: SidebarItem? { outline.item(atRow: outline.clickedRow) as? SidebarItem }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let item = clickedItem
        if item?.kind == .heading { return }
        if item?.kind == .smartFolder {
            add("Delete Smart Folder", #selector(deleteSmartFolder))
            return
        }
        add("New Document", #selector(contextNewFile))
        add("New Folder", #selector(contextNewFolder))
        guard let url = item?.url else { return }
        menu.addItem(.separator())
        if item?.kind == .section {
            add("Show in Finder", #selector(contextReveal))
            if url != Settings.shared.libraryURL { add("Remove from Library", #selector(removeLocation)) }
            return
        }
        add("Rename…", #selector(contextRename))
        add("Show in Finder", #selector(contextReveal))
        add("Move to Trash", #selector(contextTrash))
    }

    @objc func removeLocation() {
        guard let path = clickedItem?.url?.path else { return }
        Settings.shared.libraryFolders.removeAll { $0 == path }
    }

    @objc func contextNewFile() {
        if let url = createFile() { onOpen?(url) }
    }

    @objc func contextNewFolder() { createFolder() }

    @objc func contextRename() {
        if let url = clickedItem?.url { rename(url) }
    }

    @objc func contextReveal() {
        if let url = clickedItem?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func contextTrash() {
        if let url = clickedItem?.url { trash(url) }
    }

    @objc func deleteSmartFolder() {
        guard let name = clickedItem?.title else { return }
        Settings.shared.smartFolders.removeAll { $0["name"] == name }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarItem)?.children.count ?? sections.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarItem)?.children[index] ?? sections[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        let kind = (item as? SidebarItem)?.kind
        return kind != .file && kind != .heading
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarItem)?.kind == .section
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarItem)?.kind != .section
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        if item.kind == .heading {
            let identifier = NSUserInterfaceItemIdentifier("heading")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? HeadingCell ?? HeadingCell(identifier: identifier)
            cell.textField?.stringValue = item.title
            cell.textField?.textColor = item.level <= 2 ? .labelColor : .secondaryLabelColor
            cell.indent.constant = 2 + CGFloat(max(item.level - 1, 0)) * 12
            return cell
        }
        let identifier = NSUserInterfaceItemIdentifier(item.kind == .section ? "header" : "cell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier, header: item.kind == .section)
        cell.textField?.stringValue = item.title
        if let symbol = item.symbol {
            cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return cell
    }

    func makeCell(_ identifier: NSUserInterfaceItemIdentifier, header: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        if header {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.imageView = image
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !restoring, let item = outline.item(atRow: outline.selectedRow) as? SidebarItem else { return }
        if item.kind == .heading {
            onJump?(item.location)
            select(selectedURL)
            return
        }
        guard item.kind == .file, let url = item.url else { return }
        selectedURL = url
        onOpen?(url)
    }

    func isExpanded(_ item: SidebarItem) -> Bool {
        item.kind == .section ? !collapsedSections.contains(item.key) : expanded.contains(item.key)
    }

    func setExpanded(_ item: SidebarItem, _ open: Bool) {
        if item.kind == .section {
            if open { collapsedSections.remove(item.key) } else { collapsedSections.insert(item.key) }
        } else {
            if open { expanded.insert(item.key) } else { expanded.remove(item.key) }
        }
    }

    func expand(_ folder: URL) {
        expanded.insert("folder:\(folder.path)")
        collapsedSections.remove("section:\(folder.path)")
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if !restoring, let item = notification.userInfo?["NSObject"] as? SidebarItem { setExpanded(item, true) }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if !restoring, let item = notification.userInfo?["NSObject"] as? SidebarItem { setExpanded(item, false) }
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let item = item as? SidebarItem, item.kind == .file || item.kind == .folder else { return nil }
        return item.url as NSURL?
    }

    func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    func canMove(_ source: URL, into folder: URL) -> Bool {
        let source = source.standardizedFileURL.path
        let folder = folder.standardizedFileURL.path
        return (source as NSString).deletingLastPathComponent != folder && folder != source && !folder.hasPrefix(source + "/")
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard info.draggingSource as? NSOutlineView === outlineView else { return [] }
        var target = item as? SidebarItem
        if target?.kind == .file { target = outlineView.parent(forItem: target) as? SidebarItem }
        guard let target, target.isDropTarget, let folder = target.url else { return [] }
        let sources = draggedURLs(info)
        guard !sources.isEmpty, sources.allSatisfy({ canMove($0, into: folder) }) else { return [] }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let folder = (item as? SidebarItem)?.url else { return false }
        var moved = false
        for source in draggedURLs(info) where canMove(source, into: folder) {
            let target = folder.appendingPathComponent(source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path), (try? FileManager.default.moveItem(at: source, to: target)) != nil else {
                NSSound.beep()
                continue
            }
            onRenamed?(source, target)
            moved = true
        }
        expand(folder)
        reload()
        return moved
    }
}

extension LibraryNode {
    static let placeholder = LibraryIndex().scan(URL(fileURLWithPath: "/var/empty"), sort: .name)
}
