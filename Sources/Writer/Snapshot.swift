import AppKit
import WebKit
import WriterCore

enum Snapshot {
    static func capture(_ window: NSWindow, _ url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    static func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    static func run(directory: URL, controller: WindowController) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let window = controller.window else { exit(1) }
        let settings = Settings.shared
        let textView = controller.editor.textView
        func shot(_ name: String) { capture(window, directory.appendingPathComponent(name + ".png")) }
        func caret(_ needle: String, offset: Int = 0) {
            let range = textView.content.range(of: needle)
            guard range.location != NSNotFound else { return }
            textView.setSelectedRange(NSRange(location: range.location + offset, length: 0))
            textView.scrollRangeToVisible(NSRange(location: range.location, length: 0))
        }
        func menuItem(_ value: String) -> NSMenuItem {
            let item = NSMenuItem()
            item.representedObject = value
            return item
        }
        window.setContentSize(NSSize(width: 1240, height: 820))
        window.displayIfNeeded()

        after(0.8) {
            shot("01-editor")
            let rows = (NSApp.mainMenu?.items.dropFirst() ?? []).compactMap(\.submenu).flatMap { ShortcutsPanel.rows(in: $0) }
            print("SHORTCUTS", rows.count, rows.prefix(3), rows.suffix(2))
            ShortcutsPanel.shared.prepare()
            if let panel = ShortcutsPanel.shared.window {
                capture(panel, directory.appendingPathComponent("07-shortcuts.png"))
                print("SHORTCUTS panel", panel.frame.size)
            }
            if let tabs = SettingsWindowController.shared.contentViewController as? SettingsTabViewController, let settingsWindow = tabs.view.window {
                for (index, item) in tabs.tabViewItems.enumerated() {
                    tabs.selectedTabViewItemIndex = index
                    tabs.fitWindow()
                    capture(settingsWindow, directory.appendingPathComponent("09-settings-\(item.label.lowercased()).png"))
                    print("SETTINGS", item.label, settingsWindow.frame.size)
                }
                tabs.selectedTabViewItemIndex = 0
            }
            settings.syntax = Set(PartOfSpeech.allCases)
            settings.style = Set(StyleCategory.allCases)
            settings.focus = true
            caret("The beautiful old house", offset: 5)
        }
        after(1.6) {
            shot("02-focus")
            settings.focus = false
            caret("Authorship is saved")
            textView.pendingAuthor = Author.ai
            textView.insertText("This sentence was pasted from a language model. ", replacementRange: textView.selectedRange())
            textView.pendingAuthor = nil
            textView.insertText("And this one was typed. ", replacementRange: textView.selectedRange())
        }
        after(2.4) {
            shot("03-syntax-style-authors")
            settings.syntax = []
            settings.style = []
            caret("| Preview", offset: 3)
            textView.tableAction(menuItem("columnAfter"))
            textView.tableAction(menuItem("sortDescending"))
            _ = textView.moveTableCell(by: 1)
            textView.insertText("new", replacementRange: textView.selectedRange())
            textView.tableAction(menuItem("reformat"))
            if let location = MarkdownTable.locate(in: textView.content, at: textView.selectedRange().location) {
                print("TABLE\n" + textView.content.substring(with: location.range))
            }
            caret("- Lists continue", offset: 16 + 23)
            textView.insertNewline(nil)
            textView.insertText("continued item", replacementRange: textView.selectedRange())
            textView.addFootnote(nil)
            print("FOOTNOTE", textView.string.contains("[^2]: "))
            settings.appearance = "dark"
            settings.typewriter = true
            caret("Typewriter Mode", offset: 4)
        }
        after(3.4) {
            shot("04-dark-typewriter")
            ShortcutsPanel.shared.prepare()
            if let panel = ShortcutsPanel.shared.window { capture(panel, directory.appendingPathComponent("08-shortcuts-dark.png")) }
            if let layout = textView.layoutManager {
                let glyph = layout.glyphIndexForCharacter(at: textView.selectedRange().location)
                let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let clip = controller.editor.scrollView.contentView.bounds
                print("TYPEWRITER caret", Int(line.midY + textView.textContainerOrigin.y - clip.origin.y), "of", Int(clip.height))
            }
            settings.appearance = "light"
            settings.typewriter = false
            settings.showPreview = true
        }
        after(5.0) {
            controller.refreshPreview(force: true) { count in
                print("KATEX", count)
                shot("05-window-preview")
                controller.preview.webView.takeSnapshot(with: nil) { image, _ in
                    if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("06-preview.png"))
                    }
                    print("PREVIEW snapshot", image?.size ?? .zero)
                    exports()
                }
            }
        }

        @MainActor func exports() {
            let html = directory.appendingPathComponent("export.html")
            let word = directory.appendingPathComponent("export.docx")
            let pdf = directory.appendingPathComponent("export.pdf")
            try? controller.standaloneHTML().write(to: html, atomically: true, encoding: .utf8)
            try? controller.wordData()?.write(to: word)
            controller.saveDocument(nil)
            let saved = (try? String(contentsOf: controller.documentURL!, encoding: .utf8)) ?? ""
            print("ANNOTATIONS", saved.contains("\n---\nAnnotations: "), Annotations.split(saved).ranges)
            controller.printPreview(savingTo: pdf) {
                after(1.0) {
                    for url in [html, word, pdf] {
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        print("EXPORT", url.lastPathComponent, size)
                    }
                    exit(0)
                }
            }
        }
        after(20) {
            print("TIMEOUT")
            exit(2)
        }
    }
}
