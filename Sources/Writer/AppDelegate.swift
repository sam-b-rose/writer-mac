import AppKit
import Sparkle
import UniformTypeIdentifiers
import WriterCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    var controllers: [WindowController] = []
    private var pendingURLs: [URL] = []
    private var launched = false
    private lazy var updater: SPUStandardUpdaterController? = {
        guard argument("--snapshot") == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    var activeController: WindowController? {
        (NSApp.keyWindow?.windowController ?? NSApp.mainWindow?.windowController) as? WindowController ?? controllers.last
    }

    func argument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let snapshot = argument("--snapshot")
        if snapshot != nil, let store = UserDefaults(suiteName: "local.writer.mac.snapshot") {
            store.removePersistentDomain(forName: "local.writer.mac.snapshot")
            Settings.shared.store = store
        }
        if let library = argument("--library") { Settings.shared.store.set(library, forKey: "libraryPath") }
        Theme.registerFonts()
        Theme.applyAppearance()
        _ = updater
        NSApp.mainMenu = MainMenu.build(delegate: self)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.changed, object: nil)

        let controller = makeController()
        if snapshot == nil { controller.showWindow(nil) }
        controller.openInitialDocument()
        launched = true
        pendingURLs.forEach(controller.open)
        pendingURLs = []
        if let snapshot {
            Snapshot.run(directory: URL(fileURLWithPath: snapshot, isDirectory: true), controller: controller)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func makeController() -> WindowController {
        let controller = WindowController()
        controller.onClose = { [weak self] closed in self?.controllers.removeAll { $0 === closed } }
        controllers.append(controller)
        return controller
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard launched else {
            pendingURLs += urls
            return
        }
        for url in urls {
            let controller = activeController ?? makeController()
            controller.showWindow(nil)
            controller.open(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controllers.forEach { $0.appActivated() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        controllers.forEach { $0.saveIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.saveIfNeeded() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func settingsChanged(_ notification: Notification) {
        if notification.object as? String == "appearance" { Theme.applyAppearance() }
    }

    @objc func newWindow(_ sender: Any?) {
        let controller = makeController()
        controller.window?.tabbingMode = .disallowed
        controller.showWindow(nil)
        controller.window?.tabbingMode = .preferred
        controller.openInitialDocument()
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let controller = activeController ?? makeController()
        controller.showWindow(nil)
        controller.open(url)
    }

    @objc func chooseLibrary(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Settings.shared.libraryURL
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.shared.libraryFolders.removeAll { $0 == url.path }
        Settings.shared.libraryPath = url.path
    }

    @objc func addLibraryFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let settings = Settings.shared
        let path = url.standardizedFileURL.path
        let roots = [settings.libraryPath] + settings.libraryFolders
        guard !roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else {
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” overlaps a folder that is already in the library"
            alert.runModal()
            return
        }
        settings.libraryFolders.append(path)
    }

    @objc func editCustomPatterns(_ sender: Any?) {
        let url = Settings.customPatternsURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "# One word or phrase per line. Lines that start with # are ignored.\n".write(to: url, atomically: true, encoding: .utf8)
        }
        Settings.shared.style.insert(.custom)
        activeController?.open(url)
    }

    @objc func checkForUpdates(_ sender: Any?) { updater?.checkForUpdates(sender) }

    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.showWindow(nil) }

    @objc func showShortcuts(_ sender: Any?) { ShortcutsPanel.shared.toggle(over: activeController?.window) }

    @objc func toggleLibrary(_ sender: Any?) { Settings.shared.showLibrary.toggle() }
    @objc func togglePreview(_ sender: Any?) { Settings.shared.showPreview.toggle() }
    @objc func toggleFormatBar(_ sender: Any?) { Settings.shared.showFormatBar.toggle() }

    @objc func setPreviewLayout(_ sender: NSMenuItem) {
        Settings.shared.fullPreview = sender.representedObject as? String == "full"
        Settings.shared.showPreview = true
    }
    @objc func toggleFocus(_ sender: Any?) { Settings.shared.focus.toggle() }
    @objc func toggleTypewriter(_ sender: Any?) { Settings.shared.typewriter.toggle() }
    @objc func toggleSentenceLines(_ sender: Any?) { Settings.shared.sentenceLines.toggle() }
    @objc func toggleAuthors(_ sender: Any?) { Settings.shared.showAuthors.toggle() }
    @objc func toggleHardBreaks(_ sender: Any?) { Settings.shared.hardBreaks.toggle() }
    @objc func toggleSmartPunctuation(_ sender: Any?) { Settings.shared.smartPunctuation.toggle() }

    @objc func setFocusScope(_ sender: NSMenuItem) {
        Settings.shared.focusScope = sender.representedObject as? String ?? "sentence"
        Settings.shared.focus = true
    }

    @objc func toggleSyntax(_ sender: NSMenuItem) {
        guard let kind = (sender.representedObject as? String).flatMap(PartOfSpeech.init(rawValue:)) else { return }
        Settings.shared.syntax.formSymmetricDifference([kind])
    }

    @objc func toggleAllSyntax(_ sender: Any?) {
        Settings.shared.syntax = Settings.shared.syntax.isEmpty ? Set(PartOfSpeech.allCases) : []
    }

    @objc func toggleStyle(_ sender: NSMenuItem) {
        guard let category = (sender.representedObject as? String).flatMap(StyleCategory.init(rawValue:)) else { return }
        Settings.shared.style.formSymmetricDifference([category])
    }

    @objc func toggleAllStyle(_ sender: Any?) {
        Settings.shared.style = Settings.shared.style.isEmpty ? Set(StyleCategory.allCases) : []
    }

    @objc func setStat(_ sender: NSMenuItem) {
        if let kind = (sender.representedObject as? String).flatMap(StatKind.init(rawValue:)) { Settings.shared.stat = kind }
    }

    @objc func chooseFont(_ sender: NSMenuItem) {
        Settings.shared.font = sender.representedObject as? String ?? "duo"
    }

    @objc func changeSize(_ sender: NSMenuItem) {
        Settings.shared.size = sender.tag == 0 ? Settings.defaultSize : Settings.shared.size + Double(sender.tag)
    }

    @objc func chooseAppearance(_ sender: NSMenuItem) {
        Settings.shared.appearance = sender.representedObject as? String ?? "auto"
    }

    @objc func setTemplate(_ sender: NSMenuItem) {
        Settings.shared.template = sender.representedObject as? String ?? "Duo"
    }

    @objc func openTemplatesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(Settings.templatesDirectory)
    }

    @objc func setSort(_ sender: NSMenuItem) {
        if let order = (sender.representedObject as? String).flatMap(LibrarySort.init(rawValue:)) { Settings.shared.sort = order }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for name in Settings.builtInTemplates {
            menu.addItem(MainMenu.item(name, #selector(setTemplate(_:)), value: name))
        }
        let custom = Settings.customTemplates
        if !custom.isEmpty { menu.addItem(.separator()) }
        for name in custom {
            menu.addItem(MainMenu.item(name, #selector(setTemplate(_:)), value: name))
        }
        menu.addItem(.separator())
        menu.addItem(MainMenu.item("Open Templates Folder", #selector(openTemplatesFolder(_:))))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let settings = Settings.shared
        let value = menuItem.representedObject as? String
        var on: Bool?
        switch menuItem.action {
        case #selector(toggleLibrary(_:)): on = settings.showLibrary
        case #selector(togglePreview(_:)): on = settings.showPreview
        case #selector(toggleFormatBar(_:)): on = settings.showFormatBar
        case #selector(setPreviewLayout(_:)): on = settings.fullPreview == (value == "full")
        case #selector(toggleFocus(_:)): on = settings.focus
        case #selector(toggleTypewriter(_:)): on = settings.typewriter
        case #selector(toggleSentenceLines(_:)): on = settings.sentenceLines
        case #selector(toggleAuthors(_:)): on = settings.showAuthors
        case #selector(toggleHardBreaks(_:)): on = settings.hardBreaks
        case #selector(toggleSmartPunctuation(_:)): on = settings.smartPunctuation
        case #selector(setFocusScope(_:)): on = settings.focusScope == value
        case #selector(toggleSyntax(_:)): on = settings.syntax.contains { $0.rawValue == value }
        case #selector(toggleAllSyntax(_:)): on = !settings.syntax.isEmpty
        case #selector(toggleStyle(_:)): on = settings.style.contains { $0.rawValue == value }
        case #selector(toggleAllStyle(_:)): on = !settings.style.isEmpty
        case #selector(setStat(_:)): on = settings.stat.rawValue == value
        case #selector(chooseFont(_:)): on = settings.font == value
        case #selector(chooseAppearance(_:)): on = settings.appearance == value
        case #selector(setTemplate(_:)): on = settings.template == value
        case #selector(setSort(_:)): on = settings.sort.rawValue == value
        case #selector(checkForUpdates(_:)): return updater?.updater.canCheckForUpdates ?? false
        default: break
        }
        if let on { menuItem.state = on ? .on : .off }
        return true
    }
}
