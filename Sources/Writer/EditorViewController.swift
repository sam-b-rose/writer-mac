import AppKit
import WriterCore

final class CaretView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.caret.cgColor
        layer?.cornerRadius = bounds.width / 2
    }

    func blink() {
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0, 0, 1]
        animation.keyTimes = [0, 0.42, 0.58, 0.84, 1]
        animation.timingFunctions = [ease, ease, ease, ease]
        animation.duration = 1.2
        animation.repeatCount = .infinity
        layer?.removeAnimation(forKey: "blink")
        layer?.add(animation, forKey: "blink")
    }
}

final class RoundedBackgroundLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage {
            let height = defaultLineHeight(for: Theme.font())
            Theme.codeBackground.setFill()
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.backgroundColor, in: characters) { value, range, _ in
                guard (value as? NSColor) == Theme.codeBackground else { return }
                let code = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: code) { _, _, container, line, _ in
                    var box = self.boundingRect(forGlyphRange: NSIntersectionRange(line, code), in: container)
                    box = box.offsetBy(dx: origin.x, dy: origin.y)
                    box.size.height = min(box.height, height)
                    NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        guard color != Theme.codeBackground else { return }
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }
}

final class BackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.changed, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func settingsChanged(_ notification: Notification) {
        if notification.object as? String == "appearance" { needsDisplay = true }
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.background.cgColor
    }
}

final class EditorViewController: NSViewController, NSTextStorageDelegate, NSTextViewDelegate {
    static let authorKey = NSAttributedString.Key("WriterAuthor")
    static let managedKeys: [NSAttributedString.Key] = [.strikethroughStyle, .backgroundColor, .underlineStyle, .underlineColor]

    let scrollView = FindBarScrollView()
    let textView: EditorTextView
    let statsButton = NSButton(title: "", target: nil, action: nil)
    private(set) lazy var formatBar = makeFormatBar()
    let caret = CaretView()
    var overlayRange = NSRange()

    var documentURL: URL?
    var onChange: (() -> Void)?
    var onOpenLink: ((String) -> Void)?

    private var isLoading = false
    private var pendingEdit: NSRange?
    private var lastBlockCount = 0
    private var codeRanges: [NSRange] = []
    private var overlaysScheduled = false
    private var statsScheduled = false
    private let tagger = PartOfSpeechTagger()
    private var checker = StyleChecker(enabled: [], custom: [])
    private var characterWidth: CGFloat = 9

    init() {
        let storage = NSTextStorage()
        let layout = RoundedBackgroundLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        textView = EditorTextView(frame: .zero, textContainer: container)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    var storage: NSTextStorage { textView.textStorage! }
    var gutter: CGFloat { characterWidth * 7 }

    override func loadView() {
        let root = BackgroundView()
        root.wantsLayer = true
        textView.editor = self
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = .clear
        caret.wantsLayer = true
        caret.isHidden = true
        textView.addSubview(caret)
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection]
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.applyTextChecking()
        storage.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        statsButton.isBordered = false
        statsButton.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        statsButton.contentTintColor = Theme.muted
        statsButton.target = self
        statsButton.action = #selector(showStatsMenu(_:))
        statsButton.refusesFirstResponder = true

        root.addSubview(scrollView)
        formatBar.isHidden = !Settings.shared.showFormatBar
        root.addSubview(formatBar)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            formatBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            formatBar.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 12),
            formatBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        view = root

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(frameChanged), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        center.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        center.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.changed, object: nil)
        center.addObserver(self, selector: #selector(updateCaret), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(updateCaret), name: NSWindow.didResignKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(updateCaret), name: NSView.frameDidChangeNotification, object: textView)
        textView.postsFrameChangedNotifications = true
        rebuildChecker()
        restyle()
    }

    func paragraphStyle(first: CGFloat? = nil, head: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = first ?? gutter
        style.headIndent = head ?? gutter
        style.tailIndent = -gutter
        style.lineSpacing = (CGFloat(Settings.shared.size) * 0.5).rounded()
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Theme.font(), .foregroundColor: Theme.text, .paragraphStyle: paragraphStyle()]
    }

    func load(text: String, authors: [AuthorRange]) {
        isLoading = true
        textView.string = text
        for item in authors where NSMaxRange(item.range) <= storage.length {
            storage.addAttribute(Self.authorKey, value: item.author, range: item.range)
        }
        isLoading = false
        highlight(edited: nil)
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateInsets()
        refreshOverlays()
        updateStats()
        centerCaret(animated: false)
    }

    var authorRanges: [AuthorRange] {
        var ranges: [AuthorRange] = []
        storage.enumerateAttribute(Self.authorKey, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let author = value as? String { ranges.append(AuthorRange(range: range, author: author)) }
        }
        return ranges
    }

    func authorsChanged() {
        refreshOverlays()
        onChange?()
    }

    func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:], toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        newTypingAttributes.merging([.paragraphStyle: paragraphStyle()]) { $1 }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        pendingEdit = replacementString.map { NSRange(location: affectedCharRange.location, length: ($0 as NSString).length) }
        return true
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isLoading else { return }
        let undoing = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
        if !undoing, let inserted = pendingEdit, inserted.length > 0, NSMaxRange(inserted) <= textStorage.length {
            if let author = textView.pendingAuthor {
                textStorage.addAttribute(Self.authorKey, value: author, range: inserted)
            } else {
                textStorage.removeAttribute(Self.authorKey, range: inserted)
            }
        }
        pendingEdit = nil
        highlight(edited: editedRange)
    }

    func highlight(edited: NSRange?) {
        let text = storage.string as NSString
        let scan = SyntaxScanner.scan(text)
        var range = NSRange(location: 0, length: text.length)
        if let edited, scan.codeBlocks.count == lastBlockCount {
            var local = text.paragraphRange(for: NSRange(location: edited.location, length: min(edited.length + 1, text.length - edited.location)))
            let snippet = text.substring(with: local)
            if !snippet.contains("```"), !snippet.contains("~~~") {
                for span in scan.spans where (span.kind == .math || span.kind == .codeBlock) && NSIntersectionRange(span.range, local).length > 0 {
                    local = text.paragraphRange(for: NSUnionRange(local, span.range))
                }
                range = local
            }
        }
        lastBlockCount = scan.codeBlocks.count
        codeRanges = scan.spans.filter { $0.kind == .code || $0.kind == .codeBlock }.map(\.range)
        apply(scan, in: range)
    }

    func addTrait(_ trait: NSFontTraitMask, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    func apply(_ scan: ScanResult, in range: NSRange) {
        guard range.length > 0 else { return }
        let text = storage.string as NSString
        storage.addAttributes(baseAttributes, range: range)
        for key in Self.managedKeys { storage.removeAttribute(key, range: range) }
        let monoFont = Theme.font(family: Settings.shared.font == "quattro" ? "mono" : nil)
        for span in scan.spans {
            let clipped = NSIntersectionRange(span.range, range)
            guard clipped.length > 0 else { continue }
            switch span.kind {
            case .markup:
                storage.addAttribute(.foregroundColor, value: Theme.markup, range: clipped)
            case .strong:
                addTrait(.boldFontMask, in: clipped)
            case .emphasis:
                addTrait(.italicFontMask, in: clipped)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: clipped)
            case .code:
                storage.addAttributes([.font: monoFont, .backgroundColor: Theme.codeBackground], range: clipped)
            case .codeBlock:
                storage.addAttribute(.font, value: monoFont, range: clipped)
            case .link:
                storage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.markup], range: clipped)
            case .wikilink, .hashtag, .footnote, .math:
                storage.addAttribute(.foregroundColor, value: Theme.accent, range: clipped)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: Theme.highlight, range: clipped)
            case .heading(let hang):
                addTrait(.boldFontMask, in: clipped)
                let style = paragraphStyle(first: max(gutter - CGFloat(hang) * characterWidth, 0))
                storage.addAttribute(.paragraphStyle, value: style, range: NSIntersectionRange(text.paragraphRange(for: span.range), range))
            case .hanging(let indent):
                let style = paragraphStyle(head: gutter + CGFloat(indent) * characterWidth)
                storage.addAttribute(.paragraphStyle, value: style, range: clipped)
            }
        }
    }

    @objc func updateCaret() {
        let selection = textView.selectedRange()
        guard let layout = textView.layoutManager, let window = textView.window, window.isKeyWindow,
              window.firstResponder === textView, selection.length == 0 else {
            caret.isHidden = true
            return
        }
        let length = storage.length
        var line: NSRect
        var x: CGFloat
        if length == 0 || (selection.location >= length && layout.extraLineFragmentTextContainer != nil) {
            layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: length))
            line = layout.extraLineFragmentRect
            x = layout.extraLineFragmentUsedRect.minX
        } else {
            let glyph = layout.glyphIndexForCharacter(at: min(selection.location, length - 1))
            line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            x = selection.location >= length
                ? layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).maxX
                : line.minX + layout.location(forGlyphAt: glyph).x
        }
        let font = Theme.font()
        let origin = textView.textContainerOrigin
        let width = max(3, (font.pointSize / 6).rounded())
        let overshoot = (font.pointSize * 0.22).rounded()
        let frame = NSRect(
            x: (origin.x + x - width / 2).rounded(),
            y: origin.y + line.minY - overshoot,
            width: width,
            height: ceil(font.ascender - font.descender) + overshoot * 2)
        let moved = caret.isHidden || caret.frame != frame
        caret.frame = frame
        caret.isHidden = false
        if moved { caret.blink() }
    }

    func textDidChange(_ notification: Notification) {
        scheduleOverlays()
        updateCaret()
        scheduleStats()
        centerCaret(animated: true)
        onChange?()
    }

    func isCode(_ range: NSRange) -> Bool {
        codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    func textView(_ view: NSTextView, didCheckTextIn range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any] = [:], results: [NSTextCheckingResult], orthography: NSOrthography, wordCount: Int) -> [NSTextCheckingResult] {
        results.filter { ![.spelling, .grammar, .correction, .quote].contains($0.resultType) || !isCode($0.range) }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if Settings.shared.focus { scheduleOverlays() }
        updateCaret()
        scheduleStats()
        if NSApp.currentEvent?.type != .leftMouseDown, NSApp.currentEvent?.type != .leftMouseDragged {
            centerCaret(animated: true)
        }
    }

    @objc func frameChanged() {
        updateInsets()
        scheduleOverlays()
        updateCaret()
    }

    @objc func scrolled() {
        guard !Settings.shared.syntax.isEmpty || !checker.isEmpty, visibleCharacterRange != overlayRange else { return }
        scheduleOverlays()
    }

    @objc func settingsChanged(_ notification: Notification) {
        let key = notification.object as? String
        if let key, Settings.textCheckingKeys.contains(key) {
            textView.applyTextChecking()
            return
        }
        switch key {
        case "font", "size": restyle()
        case "appearance":
            restyle()
            textView.needsDisplay = true
        case "lineLength": updateInsets()
        case "style":
            rebuildChecker()
            refreshOverlays()
        case "typewriter":
            let previous = textView.textContainerInset.height
            updateInsets()
            if Settings.shared.typewriter {
                let clip = scrollView.contentView
                clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + textView.textContainerInset.height - previous))
            }
            centerCaret(animated: true)
        case "stat": updateStats()
        case "showFormatBar": formatBar.isHidden = !Settings.shared.showFormatBar
        default: refreshOverlays()
        }
    }

    func rebuildChecker() {
        checker = StyleChecker(enabled: Settings.shared.style, custom: Settings.shared.customPatterns)
    }

    func restyle() {
        characterWidth = Theme.characterWidth
        textView.typingAttributes = baseAttributes
        highlight(edited: nil)
        updateInsets()
        refreshOverlays()
        updateCaret()
    }

    func updateInsets() {
        let size = scrollView.contentSize
        let side = max(16, ((size.width - characterWidth * CGFloat(Settings.shared.lineLength)) / 2 - gutter).rounded(.down))
        let vertical = Settings.shared.typewriter ? (size.height / 2).rounded(.down) : 72
        let inset = NSSize(width: side, height: vertical)
        guard textView.textContainerInset != inset else { return }
        textView.textContainerInset = inset
        textView.sizeToFit()
    }

    var caretLine: NSRect { line(at: textView.selectedRange().location) }

    func line(at location: Int) -> NSRect {
        var rect = NSRect(x: 0, y: 0, width: 0, height: CGFloat(Settings.shared.size) * 1.5)
        guard let layout = textView.layoutManager else { return rect }
        let length = storage.length
        let location = min(location, length)
        if length > 0 {
            if location == length, layout.extraLineFragmentTextContainer != nil {
                rect = layout.extraLineFragmentRect
            } else {
                rect = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: min(location, length - 1)), effectiveRange: nil)
            }
        }
        return rect
    }

    func centerCaret(animated: Bool, at location: Int? = nil) {
        guard Settings.shared.typewriter else { return }
        let line = location.map(line(at:)) ?? caretLine
        scrollEditor(to: line.midY + textView.textContainerOrigin.y - scrollView.contentView.bounds.height / 2, animated: animated)
    }

    func jump(to location: Int) {
        textView.setSelectedRange(NSRange(location: min(location, storage.length), length: 0))
        view.window?.makeFirstResponder(textView)
        if Settings.shared.typewriter {
            centerCaret(animated: true)
        } else {
            scrollEditor(to: caretLine.minY, animated: true)
        }
    }

    func scrollEditor(to y: CGFloat, animated: Bool) {
        let clip = scrollView.contentView
        let limit = max(textView.frame.height - clip.bounds.height, 0)
        let target = NSPoint(x: 0, y: min(max(y, 0), limit))
        let distance = abs(target.y - clip.bounds.origin.y)
        if distance < 0.5 { return }
        let duration = min(max(0.12 * sqrt(distance / 30), 0.12), 0.3)
        if animated, distance < caretLine.height * 3, let layer = textView.layer {
            let offset = target.y - clip.bounds.origin.y
            clip.setBoundsOrigin(target)
            let slide = CABasicAnimation(keyPath: "position")
            slide.isAdditive = true
            slide.fromValue = NSValue(point: NSPoint(x: 0, y: offset))
            slide.toValue = NSValue(point: .zero)
            slide.duration = duration
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(slide, forKey: nil)
        } else if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                clip.animator().setBoundsOrigin(target)
            }
        } else {
            clip.setBoundsOrigin(target)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    func scheduleOverlays() {
        guard !overlaysScheduled else { return }
        overlaysScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.overlaysScheduled = false
            self?.refreshOverlays()
        }
    }

    var visibleCharacterRange: NSRange {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return NSRange() }
        let origin = textView.textContainerOrigin
        let rect = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        return (storage.string as NSString).paragraphRange(for: layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
    }

    func refreshOverlays() {
        guard isViewLoaded, let layout = textView.layoutManager else { return }
        overlayRange = visibleCharacterRange
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let keys: [NSAttributedString.Key] = [.foregroundColor, .strikethroughStyle, .strikethroughColor]
        var effective = NSRange()
        for key in keys where full.length > 0 {
            if layout.temporaryAttribute(key, atCharacterIndex: 0, longestEffectiveRange: &effective, in: full) == nil, effective == full { continue }
            layout.removeTemporaryAttribute(key, forCharacterRange: full)
        }
        let settings = Settings.shared
        let syntax = settings.syntax

        if !syntax.isEmpty || !checker.isEmpty {
            let blocks = SyntaxScanner.fencedBlocks(in: text).blocks + [Frontmatter.range(in: text)].compactMap { $0 }
            text.enumerateSubstrings(in: visibleCharacterRange, options: [.byParagraphs]) { substring, range, _, _ in
                guard let substring, !substring.isEmpty, !blocks.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
                if !syntax.isEmpty {
                    for (local, kind) in self.tagger.tags(in: substring) where syntax.contains(kind) {
                        layout.addTemporaryAttribute(
                            .foregroundColor, value: Theme.partsOfSpeech[kind]!,
                            forCharacterRange: NSRange(location: range.location + local.location, length: local.length))
                    }
                }
                for match in self.checker.matches(in: substring) {
                    layout.addTemporaryAttributes(
                        [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: Theme.styleMark],
                        forCharacterRange: NSRange(location: range.location + match.range.location, length: match.range.length))
                }
            }
        }
        if settings.showAuthors {
            storage.enumerateAttribute(Self.authorKey, in: full) { value, range, _ in
                if let author = value as? String {
                    layout.addTemporaryAttribute(.foregroundColor, value: Theme.authorColor(author), forCharacterRange: range)
                }
            }
        }
        if settings.focus, text.length > 0 {
            let location = textView.selectedRange().location
            let focus = settings.focusScope == "paragraph"
                ? TextScopes.paragraph(in: text, at: location)
                : TextScopes.sentence(in: text, at: location)
            for range in [NSRange(location: 0, length: focus.location), NSRange(location: NSMaxRange(focus), length: text.length - NSMaxRange(focus))]
            where range.length > 0 {
                layout.addTemporaryAttribute(.foregroundColor, value: Theme.dim, forCharacterRange: range)
                layout.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
            }
        }
    }

    func scheduleStats() {
        guard !statsScheduled else { return }
        statsScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.statsScheduled = false
            self?.updateStats()
        }
    }

    func updateStats() {
        let selection = (storage.string as NSString).substring(with: textView.selectedRange())
        let title = Stats.format(Settings.shared.stat, document: storage.string, selection: selection)
        if statsButton.title != title { statsButton.title = title }
    }

    static let formatButtons: [(symbol: String, title: String, action: Selector, priority: NSStackView.VisibilityPriority)] = [
        ("number", "Heading", #selector(EditorViewController.showHeadingMenu(_:)), .mustHold),
        ("bold", "Bold (⌘B)", #selector(EditorTextView.toggleBold(_:)), .mustHold),
        ("italic", "Italic (⌘I)", #selector(EditorTextView.toggleItalic(_:)), .mustHold),
        ("strikethrough", "Strikethrough (⇧⌘U)", #selector(EditorTextView.toggleStrikethrough(_:)), .detachOnlyIfNecessary),
        ("chevron.left.forwardslash.chevron.right", "Code (⌘J)", #selector(EditorTextView.toggleCode(_:)), .detachOnlyIfNecessary),
        ("link", "Link (⌘K)", #selector(EditorTextView.addLink(_:)), .mustHold),
        ("list.bullet", "List (⌥⌘L)", #selector(EditorTextView.toggleList(_:)), .mustHold),
        ("list.number", "Ordered List (⌃⌘L)", #selector(EditorTextView.toggleOrderedList(_:)), .detachOnlyIfNecessary),
        ("checklist", "Task List (⇧⌘T)", #selector(EditorTextView.toggleTaskList(_:)), .detachOnlyIfNecessary),
        ("text.quote", "Blockquote (⌘')", #selector(EditorTextView.toggleBlockquote(_:)), .detachOnlyIfNecessary),
    ]

    func makeFormatBar() -> NSView {
        let stack = NSStackView()
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 10)
        stack.setClippingResistancePriority(.defaultHigh, for: .horizontal)
        for spec in Self.formatButtons {
            let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.title)!
            let button = NSButton(image: image, target: spec.action == #selector(showHeadingMenu(_:)) ? self : textView, action: spec.action)
            button.bezelStyle = .toolbar
            button.showsBorderOnlyWhileMouseInside = true
            button.refusesFirstResponder = true
            button.toolTip = spec.title
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            stack.addView(button, in: .center)
            stack.setVisibilityPriority(spec.priority, for: button)
        }
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        stack.addView(divider, in: .center)
        stack.addView(statsButton, in: .center)

        let bar: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 18
            glass.contentView = stack
            bar = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 18
            effect.addSubview(stack)
            bar = effect
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 36),
        ])
        return bar
    }

    func popUp(_ menu: NSMenu, above sender: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -menu.size.height - 6), in: sender)
    }

    @objc func showHeadingMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for level in 0...6 {
            let item = NSMenuItem(title: level == 0 ? "Body" : "Heading \(level)", action: #selector(EditorTextView.setHeading(_:)), keyEquivalent: level == 0 ? "0" : "\(level)")
            item.keyEquivalentModifierMask = level == 0 ? [.command, .option] : [.command]
            item.tag = level
            item.target = textView
            menu.addItem(item)
        }
        popUp(menu, above: sender)
    }

    @objc func showStatsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for kind in StatKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(pickStat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = kind == Settings.shared.stat ? .on : .off
            menu.addItem(item)
        }
        popUp(menu, above: sender)
    }

    @objc func pickStat(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let kind = StatKind(rawValue: raw) { Settings.shared.stat = kind }
    }
}
