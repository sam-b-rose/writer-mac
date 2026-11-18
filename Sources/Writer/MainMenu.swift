import AppKit
import WriterCore

enum MainMenu {
    static func item(
        _ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command],
        tag: Int = 0, value: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        item.representedObject = value
        return item
    }

    static func named(_ selector: String) -> Selector { Selector((selector)) }

    static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = menu(title, items)
        return parent
    }

    static var separator: NSMenuItem { .separator() }

    static func build(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        let shift: NSEvent.ModifierFlags = [.command, .shift]
        let option: NSEvent.ModifierFlags = [.command, .option]
        let control: NSEvent.ModifierFlags = [.command, .control]

        main.addItem(submenu("Writer", [
            item("About Writer", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
            separator,
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            separator,
            item("Hide Writer", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", option),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            separator,
            item("Quit Writer", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New", #selector(WindowController.newDocument(_:)), "n"),
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n", shift),
            item("New Tab", #selector(NSResponder.newWindowForTab(_:)), "t"),
            item("New Folder…", #selector(WindowController.newFolder(_:)), "n", option),
            item("New Smart Folder…", #selector(WindowController.newSmartFolder(_:))),
            separator,
            item("Open…", #selector(AppDelegate.openDocument(_:)), "o"),
            item("Quick Search", #selector(WindowController.showQuickSearch(_:)), "o", shift),
            item("Filter Library…", #selector(WindowController.searchLibrary(_:)), "f", shift),
            item("Choose Library Folder…", #selector(AppDelegate.chooseLibrary(_:))),
            item("Add Library Folder…", #selector(AppDelegate.addLibraryFolder(_:))),
            separator,
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(WindowController.saveDocument(_:)), "s"),
            item("Rename…", #selector(WindowController.renameDocument(_:))),
            item("Browse Versions…", #selector(WindowController.browseVersions(_:))),
            item("Show in Finder", #selector(WindowController.revealDocument(_:))),
            item("Move to Trash", #selector(WindowController.trashDocument(_:)), "\u{8}", control),
            separator,
            submenu("Export", [
                item("HTML…", #selector(WindowController.exportHTML(_:))),
                item("PDF…", #selector(WindowController.exportPDF(_:))),
                item("Microsoft Word…", #selector(WindowController.exportWord(_:))),
                item("Markdown…", #selector(WindowController.exportMarkdown(_:))),
                separator,
                item("Copy HTML", #selector(WindowController.copyHTML(_:)), "c", option),
                item("Copy Formatted", #selector(WindowController.copyFormatted(_:)), "c", shift),
            ]),
            separator,
            item("Print…", #selector(WindowController.printDocument(_:)), "p"),
            item("Print Plain Text…", #selector(WindowController.printPlainText(_:)), "p", option),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", named("undo:"), "z"),
            item("Redo", named("redo:"), "z", shift),
            separator,
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            submenu("Paste As", [
                item("AI", #selector(EditorTextView.pasteAs(_:)), "v", shift, value: Author.ai),
                item("Reference", #selector(EditorTextView.pasteAs(_:)), "v", option, value: Author.reference),
                item("Other Author…", #selector(EditorTextView.pasteAsOtherAuthor(_:))),
            ]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            separator,
            submenu("Find", [
                item("Find…", #selector(NSTextView.performTextFinderAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue),
                item("Find and Replace…", #selector(NSTextView.performTextFinderAction(_:)), "f", option, tag: NSTextFinder.Action.showReplaceInterface.rawValue),
                item("Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue),
                item("Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g", shift, tag: NSTextFinder.Action.previousMatch.rawValue),
                item("Use Selection for Find", #selector(NSTextView.performTextFinderAction(_:)), "e", tag: NSTextFinder.Action.setSearchString.rawValue),
            ]),
            submenu("Spelling and Grammar", [
                item("Show Spelling and Grammar", named("showGuessPanel:"), ":"),
                item("Check Document Now", named("checkSpelling:"), ";"),
                separator,
                item("Check Spelling While Typing", named("toggleContinuousSpellChecking:")),
                item("Check Grammar With Spelling", named("toggleGrammarChecking:")),
                item("Correct Spelling Automatically", named("toggleAutomaticSpellingCorrection:")),
            ]),
            submenu("Substitutions", [
                item("Show Substitutions", named("orderFrontSubstitutionsPanel:")),
                separator,
                item("Smart Copy/Paste", named("toggleSmartInsertDelete:")),
                item("Smart Quotes", named("toggleAutomaticQuoteSubstitution:")),
                item("Smart Dashes", named("toggleAutomaticDashSubstitution:")),
                item("Text Replacement", named("toggleAutomaticTextReplacement:")),
            ]),
            submenu("Transformations", [
                item("Make Upper Case", named("uppercaseWord:")),
                item("Make Lower Case", named("lowercaseWord:")),
                item("Capitalize", named("capitalizeWord:")),
            ]),
            submenu("Speech", [
                item("Start Speaking", named("startSpeaking:")),
                item("Stop Speaking", named("stopSpeaking:")),
            ]),
            item("Show Completions", named("complete:"), "\u{1b}", [.option]),
        ]))

        let headings = [item("Body", #selector(EditorTextView.setHeading(_:)), "0", option, tag: 0)]
            + (1...6).map { item("Heading \($0)", #selector(EditorTextView.setHeading(_:)), "\($0)", tag: $0) }
        let tableItems: [(String, String)] = [
            ("Add Row Above", "rowAbove"), ("Add Row Below", "rowBelow"), ("Add Column Before", "columnBefore"),
            ("Add Column After", "columnAfter"), ("-", ""), ("Move Row Up", "rowUp"), ("Move Row Down", "rowDown"),
            ("Move Column Left", "columnLeft"), ("Move Column Right", "columnRight"), ("-", ""),
            ("Align Column Left", "alignLeft"), ("Align Column Center", "alignCenter"), ("Align Column Right", "alignRight"),
            ("-", ""), ("Sort Column Ascending", "sortAscending"), ("Sort Column Descending", "sortDescending"),
            ("-", ""), ("Delete Row", "deleteRow"), ("Delete Column", "deleteColumn"), ("-", ""), ("Reformat Table", "reformat"),
        ]
        main.addItem(submenu("Format", [
            submenu("Heading", headings),
            separator,
            item("Bold", #selector(EditorTextView.toggleBold(_:)), "b"),
            item("Italic", #selector(EditorTextView.toggleItalic(_:)), "i"),
            item("Strikethrough", #selector(EditorTextView.toggleStrikethrough(_:)), "u", shift),
            item("Highlight", #selector(EditorTextView.toggleHighlight(_:)), "e", shift),
            item("Code", #selector(EditorTextView.toggleCode(_:)), "j"),
            item("Code Block", #selector(EditorTextView.toggleCodeBlock(_:)), "j", shift),
            separator,
            item("List", #selector(EditorTextView.toggleList(_:)), "l", option),
            item("Ordered List", #selector(EditorTextView.toggleOrderedList(_:)), "l", control),
            item("Task List", #selector(EditorTextView.toggleTaskList(_:)), "t", shift),
            item("Mark Task as Completed", #selector(EditorTextView.toggleTaskCompleted(_:)), "l"),
            item("Blockquote", #selector(EditorTextView.toggleBlockquote(_:)), "'"),
            submenu("Callout", ["Note", "Tip", "Important", "Warning", "Caution"].map {
                item($0, #selector(EditorTextView.addCallout(_:)), value: $0.uppercased())
            }),
            separator,
            submenu("Table", tableItems.map { title, operation in
                title == "-" ? separator : item(title, #selector(EditorTextView.tableAction(_:)), value: operation)
            }),
        ]))

        main.addItem(submenu("Insert", [
            item("Link", #selector(EditorTextView.addLink(_:)), "k"),
            item("Wikilink", #selector(EditorTextView.addWikilink(_:)), "k", shift),
            item("Image", #selector(EditorTextView.addImage(_:)), "k", option),
            item("Footnote", #selector(EditorTextView.addFootnote(_:)), "n", control),
            item("Hashtag", #selector(EditorTextView.addHashtag(_:))),
            item("Date", #selector(EditorTextView.addDate(_:)), "d", shift),
            separator,
            item("Table", #selector(EditorTextView.addTable(_:)), "t", control),
            submenu("Math", [
                item("Inline Math", #selector(EditorTextView.toggleInlineMath(_:)), "m", control),
                item("Display Math", #selector(EditorTextView.addDisplayMath(_:))),
            ]),
            item("Horizontal Rule", #selector(EditorTextView.addHorizontalRule(_:))),
            item("Page Break", #selector(EditorTextView.addPageBreak(_:)), "\r", shift),
            separator,
            item("Table of Contents", #selector(EditorTextView.addTableOfContents(_:))),
            item("Content Block…", #selector(EditorTextView.addContentBlock(_:))),
        ]))

        main.addItem(submenu("Writing", [
            item("Focus Mode", #selector(AppDelegate.toggleFocus(_:)), "d"),
            submenu("Focus", [
                item("Sentence", #selector(AppDelegate.setFocusScope(_:)), value: "sentence"),
                item("Paragraph", #selector(AppDelegate.setFocusScope(_:)), value: "paragraph"),
            ]),
            item("Typewriter Mode", #selector(AppDelegate.toggleTypewriter(_:)), "t", option),
            item("One Sentence Per Line", #selector(AppDelegate.toggleSentenceLines(_:))),
            separator,
            submenu("Syntax", [item("Show Syntax", #selector(AppDelegate.toggleAllSyntax(_:)), "h", shift), separator]
                + PartOfSpeech.allCases.map { kind in
                    let entry = item(kind.title, #selector(AppDelegate.toggleSyntax(_:)), value: kind.rawValue)
                    entry.attributedTitle = NSAttributedString(
                        string: kind.title, attributes: [.foregroundColor: Theme.partsOfSpeech[kind] ?? .labelColor])
                    return entry
                }),
            submenu("Style Check", [item("Enable Style Check", #selector(AppDelegate.toggleAllStyle(_:)), "k", control), separator]
                + StyleCategory.allCases.map { item($0.title, #selector(AppDelegate.toggleStyle(_:)), value: $0.rawValue) }
                + [separator, item("Edit Custom Patterns…", #selector(AppDelegate.editCustomPatterns(_:)))]),
            item("Show Authors", #selector(AppDelegate.toggleAuthors(_:))),
            separator,
            submenu("Mark As", [
                item("Human", #selector(EditorTextView.markAs(_:))),
                item("AI", #selector(EditorTextView.markAs(_:)), value: Author.ai),
                item("Reference", #selector(EditorTextView.markAs(_:)), value: Author.reference),
                item("Other Author…", #selector(EditorTextView.markAsOtherAuthor(_:))),
            ]),
            submenu("Stats", StatKind.allCases.map { item($0.title, #selector(AppDelegate.setStat(_:)), value: $0.rawValue) }),
        ]))

        let templates = submenu("Template", [])
        templates.submenu?.delegate = delegate
        main.addItem(submenu("View", [
            item("Show Library", #selector(AppDelegate.toggleLibrary(_:)), "l", shift),
            item("Show Preview", #selector(AppDelegate.togglePreview(_:)), "r"),
            submenu("Preview Layout", [
                item("Split", #selector(AppDelegate.setPreviewLayout(_:)), value: "split"),
                item("Full", #selector(AppDelegate.setPreviewLayout(_:)), value: "full"),
            ]),
            item("Show Formatting Bar", #selector(AppDelegate.toggleFormatBar(_:))),
            submenu("Sort Files By", LibrarySort.allCases.map { item($0.title, #selector(AppDelegate.setSort(_:)), value: $0.rawValue) }),
            separator,
            submenu("Font", [("Mono", "mono"), ("Duo", "duo"), ("Quattro", "quattro")].map {
                item($0.0, #selector(AppDelegate.chooseFont(_:)), value: $0.1)
            }),
            submenu("Text Size", [
                item("Make Text Bigger", #selector(AppDelegate.changeSize(_:)), "+", tag: 1),
                item("Make Text Smaller", #selector(AppDelegate.changeSize(_:)), "-", tag: -1),
                item("Make Text Normal Size", #selector(AppDelegate.changeSize(_:)), "0", tag: 0),
            ]),
            submenu("Appearance", [("Match System", "auto"), ("Light", "light"), ("Dark", "dark")].map {
                item($0.0, #selector(AppDelegate.chooseAppearance(_:)), value: $0.1)
            }),
            separator,
            templates,
            item("Single Return Starts a New Paragraph", #selector(AppDelegate.toggleHardBreaks(_:))),
            item("Smart Punctuation in Preview", #selector(AppDelegate.toggleSmartPunctuation(_:))),
            separator,
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", control),
        ]))

        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            separator,
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        let help = submenu("Help", [item("Keyboard Shortcuts", #selector(AppDelegate.showShortcuts(_:)), "/")])
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
    }
}
