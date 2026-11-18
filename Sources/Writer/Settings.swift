import AppKit
import WriterCore

final class Settings {
    static let shared = Settings()
    static let changed = Notification.Name("WriterSettingsChanged")
    static let defaultSize = 22.0

    var store = UserDefaults.standard

    private func read<T>(_ key: String, _ fallback: T) -> T {
        store.object(forKey: key) as? T ?? fallback
    }

    private func write(_ key: String, _ value: Any?) {
        store.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: key)
    }

    var focus: Bool {
        get { read("focus", false) }
        set { write("focus", newValue) }
    }

    var focusScope: String {
        get { read("focusScope", "sentence") }
        set { write("focusScope", newValue) }
    }

    var typewriter: Bool {
        get { read("typewriter", false) }
        set { write("typewriter", newValue) }
    }

    var sentenceLines: Bool {
        get { read("sentenceLines", false) }
        set { write("sentenceLines", newValue) }
    }

    var syntax: Set<PartOfSpeech> {
        get { Set(read("syntax", [String]()).compactMap(PartOfSpeech.init(rawValue:))) }
        set { write("syntax", newValue.map(\.rawValue)) }
    }

    var style: Set<StyleCategory> {
        get { Set(read("style", [String]()).compactMap(StyleCategory.init(rawValue:))) }
        set { write("style", newValue.map(\.rawValue)) }
    }

    var showAuthors: Bool {
        get { read("showAuthors", true) }
        set { write("showAuthors", newValue) }
    }

    var font: String {
        get { read("font", "duo") }
        set { write("font", newValue) }
    }

    var size: Double {
        get { read("size", Settings.defaultSize) }
        set { write("size", min(max(newValue, 11), 32)) }
    }

    var appearance: String {
        get { read("appearance", "auto") }
        set { write("appearance", newValue) }
    }

    var stat: StatKind {
        get { StatKind(rawValue: read("stat", "words")) ?? .words }
        set { write("stat", newValue.rawValue) }
    }

    var template: String {
        get { read("template", "Duo") }
        set { write("template", newValue) }
    }

    var hardBreaks: Bool {
        get { read("hardBreaks", false) }
        set { write("hardBreaks", newValue) }
    }

    var smartPunctuation: Bool {
        get { read("smartPunctuation", true) }
        set { write("smartPunctuation", newValue) }
    }

    var sort: LibrarySort {
        get { LibrarySort(rawValue: read("sort", "name")) ?? .name }
        set { write("sort", newValue.rawValue) }
    }

    var showLibrary: Bool {
        get { read("showLibrary", true) }
        set { write("showLibrary", newValue) }
    }

    var showPreview: Bool {
        get { read("showPreview", false) }
        set { write("showPreview", newValue) }
    }

    var showFormatBar: Bool {
        get { read("showFormatBar", true) }
        set { write("showFormatBar", newValue) }
    }

    var fullPreview: Bool {
        get { read("fullPreview", false) }
        set { write("fullPreview", newValue) }
    }

    var libraryPath: String {
        get { read("libraryPath", FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Writer").path) }
        set { write("libraryPath", newValue) }
    }

    var libraryFolders: [String] {
        get { read("libraryFolders", [String]()) }
        set { write("libraryFolders", newValue) }
    }

    var lastDocument: String? {
        get { store.string(forKey: "lastDocument") }
        set { store.set(newValue, forKey: "lastDocument") }
    }

    var smartFolders: [[String: String]] {
        get { read("smartFolders", [[String: String]]()) }
        set { write("smartFolders", newValue) }
    }

    var lineLength: Int {
        get { read("lineLength", 64) }
        set { write("lineLength", newValue) }
    }

    var syncPreviewScroll: Bool {
        get { read("syncPreviewScroll", true) }
        set { write("syncPreviewScroll", newValue) }
    }

    var sortReversed: Bool {
        get { read("sortReversed", false) }
        set { write("sortReversed", newValue) }
    }

    var showSmartFolders: Bool {
        get { read("showSmartFolders", true) }
        set { write("showSmartFolders", newValue) }
    }

    var showHashtags: Bool {
        get { read("showHashtags", true) }
        set { write("showHashtags", newValue) }
    }

    var defaultExtension: String {
        get { read("defaultExtension", "md") }
        set { write("defaultExtension", newValue) }
    }

    var boldMarker: String {
        get { read("boldMarker", "**") }
        set { write("boldMarker", newValue) }
    }

    var italicMarker: String {
        get { read("italicMarker", "*") }
        set { write("italicMarker", newValue) }
    }

    var listBullet: String {
        get { read("listBullet", "-") }
        set { write("listBullet", newValue) }
    }

    var orderedListDelimiter: String {
        get { read("orderedListDelimiter", ".") }
        set { write("orderedListDelimiter", newValue) }
    }

    var indentWithTabs: Bool {
        get { read("indentWithTabs", false) }
        set { write("indentWithTabs", newValue) }
    }

    var indentWidth: Int {
        get { read("indentWidth", 4) }
        set { write("indentWidth", newValue) }
    }

    var indentUnit: String { indentWithTabs ? "\t" : String(repeating: " ", count: indentWidth) }

    static let textCheckingKeys: Set<String> = [
        "checkSpelling", "checkGrammar", "correctSpelling", "smartQuotes", "smartDashes", "textReplacement", "smartCopyPaste", "inlinePrediction",
    ]

    var checkSpelling: Bool {
        get { read("checkSpelling", true) }
        set { write("checkSpelling", newValue) }
    }

    var checkGrammar: Bool {
        get { read("checkGrammar", false) }
        set { write("checkGrammar", newValue) }
    }

    var correctSpelling: Bool {
        get { read("correctSpelling", NSSpellChecker.isAutomaticSpellingCorrectionEnabled) }
        set { write("correctSpelling", newValue) }
    }

    var smartQuotes: Bool {
        get { read("smartQuotes", true) }
        set { write("smartQuotes", newValue) }
    }

    var smartDashes: Bool {
        get { read("smartDashes", false) }
        set { write("smartDashes", newValue) }
    }

    var textReplacement: Bool {
        get { read("textReplacement", NSSpellChecker.isAutomaticTextReplacementEnabled) }
        set { write("textReplacement", newValue) }
    }

    var smartCopyPaste: Bool {
        get { read("smartCopyPaste", false) }
        set { write("smartCopyPaste", newValue) }
    }

    var inlinePrediction: Bool {
        get { read("inlinePrediction", true) }
        set { write("inlinePrediction", newValue) }
    }

    var libraryURL: URL { URL(fileURLWithPath: libraryPath, isDirectory: true) }

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Writer")
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("Templates"), withIntermediateDirectories: true)
        return url
    }

    static var templatesDirectory: URL { supportDirectory.appendingPathComponent("Templates") }
    static var customPatternsURL: URL { supportDirectory.appendingPathComponent("Style Check Patterns.txt") }

    static let builtInTemplates = ["Duo", "Mono", "Quattro", "Sans", "Serif", "GitHub"]

    static var customTemplates: [String] {
        ((try? FileManager.default.contentsOfDirectory(at: templatesDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "css" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    var customPatterns: [String] {
        StyleChecker.parseCustom((try? String(contentsOf: Self.customPatternsURL, encoding: .utf8)) ?? "")
    }
}
