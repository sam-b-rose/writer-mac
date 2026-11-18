import AppKit
import WriterCore

final class EditorTextView: NSTextView {
    weak var editor: EditorViewController?
    var pendingAuthor: String?

    static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    static let blockPrefix = regex("^[ \\t]*(?:#{1,6}[ \\t]+|(?:[-*+]|\\d+[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?|(?:>[ \\t]?)+)")
    static let continuation = regex("^([ \\t]*)([-*+]|\\d+[.)]|>)[ \\t]+(\\[[ xX]\\][ \\t]+)?")
    static let taskBox = regex("^([ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+\\[)([ xX])\\]")
    static let footnoteNumber = regex("\\[\\^(\\d+)\\]")
    static let wikilink = regex("\\[\\[([^\\]|\\n]+)(?:\\|[^\\]\\n]+)?\\]\\]")
    static let inlineLink = regex("\\[[^\\]\\n]*\\]\\(([^)\\s]+)[^)\\n]*\\)")
    static let bareURL = regex("https?://[^\\s<>)\\]]+")

    var content: NSString { string as NSString }

    func edit(_ range: NSRange, _ replacement: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    func length(_ string: String) -> Int { (string as NSString).length }

    func wrap(_ open: String, _ close: String? = nil) {
        let close = close ?? open
        let range = selectedRange()
        let text = content
        let o = length(open)
        let c = length(close)
        if range.location >= o, NSMaxRange(range) + c <= text.length,
           text.substring(with: NSRange(location: range.location - o, length: o)) == open,
           text.substring(with: NSRange(location: NSMaxRange(range), length: c)) == close {
            edit(NSRange(location: range.location - o, length: range.length + o + c), text.substring(with: range),
                 select: NSRange(location: range.location - o, length: range.length))
        } else {
            edit(range, open + text.substring(with: range) + close, select: NSRange(location: range.location + o, length: range.length))
        }
    }

    func setPrefix(_ make: (Int) -> String) {
        let range = content.lineRange(for: selectedRange())
        var lines = content.substring(with: range).components(separatedBy: "\n")
        let trailing = lines.count > 1 && lines.last == ""
        if trailing { lines.removeLast() }
        lines = lines.enumerated().map { index, line in
            let source = line as NSString
            let existing = Self.blockPrefix.firstMatch(in: line, range: NSRange(location: 0, length: source.length))?.range.length ?? 0
            let bare = source.substring(from: existing)
            let prefix = make(index)
            return source.substring(to: existing) == prefix ? bare : prefix + bare
        }
        let joined = lines.joined(separator: "\n")
        edit(range, joined + (trailing ? "\n" : ""), select: NSRange(location: range.location + length(joined), length: 0))
    }

    func insertBlock(_ block: String, cursorOffset: Int? = nil) {
        let range = selectedRange()
        let text = content
        let before = text.substring(to: range.location)
        let after = text.substring(from: NSMaxRange(range))
        let prefix = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let suffix = after.isEmpty ? "\n" : after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
        let caret = range.location + length(prefix) + (cursorOffset ?? length(block))
        edit(range, prefix + block + suffix, select: NSRange(location: caret, length: 0))
    }

    @objc func toggleBold(_ sender: Any?) { wrap(Settings.shared.boldMarker) }
    @objc func toggleItalic(_ sender: Any?) { wrap(Settings.shared.italicMarker) }
    @objc func toggleStrikethrough(_ sender: Any?) { wrap("~~") }
    @objc func toggleHighlight(_ sender: Any?) { wrap("==") }
    @objc func toggleCode(_ sender: Any?) { wrap("`") }
    @objc func toggleInlineMath(_ sender: Any?) { wrap("$") }
    @objc func addWikilink(_ sender: Any?) { wrap("[[", "]]") }

    @objc func addLink(_ sender: Any?) {
        let range = selectedRange()
        let selected = content.substring(with: range)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            edit(range, "[](\(selected))", select: NSRange(location: range.location + 1, length: 0))
        } else {
            edit(range, "[\(selected)]()", select: NSRange(location: range.location + range.length + 3, length: 0))
        }
    }

    @objc func addImage(_ sender: Any?) {
        let range = selectedRange()
        edit(range, "![\(content.substring(with: range))]()", select: NSRange(location: range.location + range.length + 4, length: 0))
    }

    @objc func setHeading(_ sender: NSMenuItem) {
        let prefix = sender.tag == 0 ? "" : String(repeating: "#", count: sender.tag) + " "
        setPrefix { _ in prefix }
    }

    @objc func toggleList(_ sender: Any?) { setPrefix { _ in Settings.shared.listBullet + " " } }
    @objc func toggleOrderedList(_ sender: Any?) { setPrefix { "\($0 + 1)\(Settings.shared.orderedListDelimiter) " } }
    @objc func toggleTaskList(_ sender: Any?) { setPrefix { _ in Settings.shared.listBullet + " [ ] " } }
    @objc func toggleBlockquote(_ sender: Any?) { setPrefix { _ in "> " } }

    @objc func toggleCodeBlock(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            insertBlock("```\n\(content.substring(with: range))\n```")
        } else {
            insertBlock("```\n\n```", cursorOffset: 4)
        }
    }

    @objc func addCallout(_ sender: NSMenuItem) {
        insertBlock("> [!\((sender.representedObject as? String ?? "NOTE"))]\n> ")
    }

    @objc func addTable(_ sender: Any?) { insertBlock(MarkdownTable(rows: 3, columns: 3).render(), cursorOffset: 2) }
    @objc func addTableOfContents(_ sender: Any?) { insertBlock("{{TOC}}") }
    @objc func addPageBreak(_ sender: Any?) { insertBlock("+++") }
    @objc func addHorizontalRule(_ sender: Any?) { insertBlock("---") }
    @objc func addDisplayMath(_ sender: Any?) { insertBlock("$$\n\n$$", cursorOffset: 3) }
    @objc func addHashtag(_ sender: Any?) { insertText("#", replacementRange: selectedRange()) }

    @objc func addDate(_ sender: Any?) {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        insertText(formatter.string(from: Date()), replacementRange: selectedRange())
    }

    @objc func addFootnote(_ sender: Any?) {
        let text = content
        let highest = Self.footnoteNumber.matches(in: string, range: NSRange(location: 0, length: text.length))
            .compactMap { Int(text.substring(with: $0.range(at: 1))) }.max() ?? 0
        let marker = "[^\(highest + 1)]"
        let range = selectedRange()
        let definition = (string.hasSuffix("\n") ? "\n" : "\n\n") + marker + ": "
        edit(range, marker)
        let end = content.length
        edit(NSRange(location: end, length: 0), definition, select: NSRange(location: end + length(definition), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    @objc func addContentBlock(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.directoryURL = editor?.documentURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let base = (self.editor?.documentURL?.deletingLastPathComponent().path ?? "") + "/"
            let path = url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : String(url.path.dropFirst())
            self.insertBlock("/" + path)
        }
    }

    @objc func toggleTaskCompleted(_ sender: Any?) {
        let line = content.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        guard let match = Self.taskBox.firstMatch(in: string, range: line) else {
            toggleTaskList(sender)
            return
        }
        let box = match.range(at: 2)
        let caret = selectedRange()
        edit(box, content.substring(with: box) == " " ? "x" : " ", select: caret)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if Settings.shared.sentenceLines, string as? String == " ", selectedRange().length == 0, endsSentence {
            super.insertText("\n", replacementRange: replacementRange)
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    var endsSentence: Bool {
        let caret = selectedRange().location
        guard caret > 0, editor?.isCode(NSRange(location: caret - 1, length: 1)) != true else { return false }
        let line = content.lineRange(for: NSRange(location: caret, length: 0))
        return SentenceBreak.shouldBreak(after: content.substring(with: NSRange(location: line.location, length: caret - line.location)))
    }

    override func insertNewline(_ sender: Any?) {
        let range = selectedRange()
        let text = content
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let head = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
        let source = head as NSString
        guard range.length == 0,
              let match = Self.continuation.firstMatch(in: head, range: NSRange(location: 0, length: source.length)) else {
            super.insertNewline(sender)
            return
        }
        let rest = source.substring(from: NSMaxRange(match.range))
        let lineEnd = text.substring(with: NSRange(location: range.location, length: NSMaxRange(line) - range.location))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty, lineEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            edit(NSRange(location: line.location, length: range.location - line.location), "")
            return
        }
        let indent = source.substring(with: match.range(at: 1))
        var marker = source.substring(with: match.range(at: 2))
        if let number = Int(marker.dropLast()), let delimiter = marker.last { marker = "\(number + 1)\(delimiter)" }
        let task = match.range(at: 3).location != NSNotFound ? "[ ] " : ""
        insertText("\n\(indent)\(marker) \(task)", replacementRange: range)
    }

    var isListLine: Bool {
        let line = content.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        return Self.continuation.firstMatch(in: string, range: line) != nil
    }

    override func insertTab(_ sender: Any?) {
        if moveTableCell(by: 1) { return }
        if isListLine {
            let line = content.lineRange(for: NSRange(location: selectedRange().location, length: 0))
            let caret = selectedRange()
            let unit = Settings.shared.indentUnit
            edit(NSRange(location: line.location, length: 0), unit, select: NSRange(location: caret.location + length(unit), length: caret.length))
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if moveTableCell(by: -1) { return }
        let line = content.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let text = content.substring(with: line)
        let remove = text.hasPrefix("\t") ? 1 : min(Settings.shared.indentWidth, text.prefix { $0 == " " }.count)
        guard remove > 0 else { return }
        let caret = selectedRange()
        edit(NSRange(location: line.location, length: remove), "", select: NSRange(location: max(caret.location - remove, line.location), length: 0))
    }

    func replaceTable(_ location: MarkdownTable.Location, with table: MarkdownTable, row: Int, column: Int) {
        let rendered = table.render()
        let caret = NSRange(location: location.range.location + table.offset(row: row, column: column), length: 0)
        if rendered == content.substring(with: location.range) {
            setSelectedRange(caret)
        } else {
            edit(location.range, rendered, select: caret)
        }
    }

    func moveTableCell(by delta: Int) -> Bool {
        let range = selectedRange()
        guard range.length == 0, let location = MarkdownTable.locate(in: content, at: range.location) else { return false }
        var table = location.table
        let index = location.row * table.columnCount + location.column + delta
        guard index >= 0 else { return true }
        if index >= table.rows.count * table.columnCount { table.insertRow(at: table.rows.count) }
        replaceTable(location, with: table, row: index / table.columnCount, column: index % table.columnCount)
        return true
    }

    @objc func tableAction(_ sender: NSMenuItem) {
        guard let operation = sender.representedObject as? String,
              let location = MarkdownTable.locate(in: content, at: selectedRange().location) else { return }
        var table = location.table
        var row = location.row
        var column = location.column
        switch operation {
        case "rowAbove":
            row = max(row, 1)
            table.insertRow(at: row)
        case "rowBelow":
            row += 1
            table.insertRow(at: row)
        case "columnBefore": table.insertColumn(at: column)
        case "columnAfter":
            column += 1
            table.insertColumn(at: column)
        case "deleteRow":
            table.deleteRow(row)
            row = min(row, table.rows.count - 1)
        case "deleteColumn":
            table.deleteColumn(column)
            column = min(column, table.columnCount - 1)
        case "rowUp": row = table.moveRow(row, by: -1)
        case "rowDown": row = table.moveRow(row, by: 1)
        case "columnLeft": column = table.moveColumn(column, by: -1)
        case "columnRight": column = table.moveColumn(column, by: 1)
        case "alignLeft": table.alignments[column] = .left
        case "alignCenter": table.alignments[column] = .center
        case "alignRight": table.alignments[column] = .right
        case "sortAscending": table.sort(column: column, ascending: true)
        case "sortDescending": table.sort(column: column, ascending: false)
        default: break
        }
        replaceTable(location, with: table, row: row, column: column)
    }

    @objc func pasteAs(_ sender: NSMenuItem) {
        guard let author = sender.representedObject as? String else { return }
        pendingAuthor = author
        pasteAsPlainText(nil)
        pendingAuthor = nil
    }

    func promptForAuthor() -> String? {
        let alert = NSAlert()
        alert.messageText = "Author Name"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : Author.named(name)
    }

    @objc func pasteAsOtherAuthor(_ sender: Any?) {
        guard let author = promptForAuthor() else { return }
        pendingAuthor = author
        pasteAsPlainText(nil)
        pendingAuthor = nil
    }

    func mark(_ author: String?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        if let author {
            storage.addAttribute(EditorViewController.authorKey, value: author, range: range)
        } else {
            storage.removeAttribute(EditorViewController.authorKey, range: range)
        }
        editor?.authorsChanged()
    }

    @objc func markAs(_ sender: NSMenuItem) { mark(sender.representedObject as? String) }

    @objc func markAsOtherAuthor(_ sender: Any?) {
        if let author = promptForAuthor() { mark(author) }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(tableAction(_:)):
            return MarkdownTable.locate(in: content, at: selectedRange().location) != nil
        case #selector(markAs(_:)), #selector(markAsOtherAuthor(_:)):
            return selectedRange().length > 0
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    func linkTarget(at index: Int) -> String? {
        let text = content
        guard index <= text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        for (regex, prefix) in [(Self.wikilink, "wiki:"), (Self.inlineLink, ""), (Self.bareURL, "")] {
            for match in regex.matches(in: string, range: line) where NSLocationInRange(index, match.range) {
                let target = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                return prefix + text.substring(with: target).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let target = linkTarget(at: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))) {
            editor?.onOpenLink?(target)
            return
        }
        super.mouseDown(with: event)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + [.fileURL] }

    func droppedImages(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { WindowController.imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        droppedImages(dragInfo).isEmpty ? super.dragOperation(for: dragInfo, type: type) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = droppedImages(sender)
        guard !images.isEmpty, let folder = editor?.documentURL?.deletingLastPathComponent() else {
            return super.performDragOperation(sender)
        }
        let paths = images.compactMap { attach($0, to: folder) }
        guard !paths.isEmpty else { return false }
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), length: 0))
        insertBlock(paths.map { "/" + $0 }.joined(separator: "\n"))
        window?.makeFirstResponder(self)
        return true
    }

    func attach(_ image: URL, to folder: URL) -> String? {
        let base = folder.standardizedFileURL.path + "/"
        let source = image.standardizedFileURL.path
        if source.hasPrefix(base) { return String(source.dropFirst(base.count)) }
        let name = image.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(image.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(name) \(counter)").appendingPathExtension(image.pathExtension)
            counter += 1
        }
        guard (try? FileManager.default.copyItem(at: image, to: target)) != nil else { return nil }
        return target.lastPathComponent
    }

    func applyTextChecking() {
        let settings = Settings.shared
        isContinuousSpellCheckingEnabled = settings.checkSpelling
        isGrammarCheckingEnabled = settings.checkGrammar
        isAutomaticSpellingCorrectionEnabled = settings.correctSpelling
        isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        isAutomaticDashSubstitutionEnabled = settings.smartDashes
        isAutomaticTextReplacementEnabled = settings.textReplacement
        smartInsertDeleteEnabled = settings.smartCopyPaste
        inlinePredictionType = settings.inlinePrediction ? .default : .no
    }

    override func setSpellingState(_ value: Int, range charRange: NSRange) {
        if value != 0, editor?.isCode(charRange) == true { return }
        super.setSpellingState(value, range: charRange)
    }

    override func toggleContinuousSpellChecking(_ sender: Any?) { Settings.shared.checkSpelling.toggle() }
    override func toggleGrammarChecking(_ sender: Any?) { Settings.shared.checkGrammar.toggle() }
    override func toggleAutomaticSpellingCorrection(_ sender: Any?) { Settings.shared.correctSpelling.toggle() }
    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) { Settings.shared.smartQuotes.toggle() }
    override func toggleAutomaticDashSubstitution(_ sender: Any?) { Settings.shared.smartDashes.toggle() }
    override func toggleAutomaticTextReplacement(_ sender: Any?) { Settings.shared.textReplacement.toggle() }
    override func toggleSmartInsertDelete(_ sender: Any?) { Settings.shared.smartCopyPaste.toggle() }

    override func scrollRangeToVisible(_ range: NSRange) {
        if Settings.shared.typewriter { return }
        super.scrollRangeToVisible(range)
    }

    override func viewDidEndLiveResize() {
        guard let clip = enclosingScrollView?.contentView else { return super.viewDidEndLiveResize() }
        let origin = clip.bounds.origin
        super.viewDidEndLiveResize()
        clip.setBoundsOrigin(origin)
        editor?.centerCaret(animated: false)
    }
}
