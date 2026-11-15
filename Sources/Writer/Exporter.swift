import AppKit
import UniformTypeIdentifiers
import WebKit
import WriterCore

extension WindowController {
    static let fontFace = try! NSRegularExpression(pattern: "@font-face \\{[^}]*\\}\\n?")

    var exportTitle: String { documentURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    func templateCSS() -> String {
        func read(_ url: URL?) -> String { url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }
        let name = Settings.shared.template
        let base = read(Bundle.main.resourceURL?.appendingPathComponent("Templates/base.css"))
        let stripped = Self.fontFace.stringByReplacingMatches(in: base, range: NSRange(location: 0, length: (base as NSString).length), withTemplate: "")
        let template = Settings.builtInTemplates.contains(name)
            ? read(Bundle.main.resourceURL?.appendingPathComponent("Templates/\(name.lowercased()).css"))
            : read(Settings.templatesDirectory.appendingPathComponent("\(name).css"))
        return stripped + "\n" + template
    }

    func standaloneHTML() -> String {
        let body = renderHTML()
        let math = body.contains("class=\"math ") ? """
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.19.1/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.19.1/dist/katex.min.js"></script>
        <script>
        addEventListener('DOMContentLoaded', function () {
          document.querySelectorAll('.math').forEach(function (el) {
            katex.render(el.textContent, el, { displayMode: el.classList.contains('display'), throwOnError: false });
          });
        });
        </script>

        """ : ""
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(MarkdownRenderer.escape(exportTitle))</title>
        <style>
        \(templateCSS())
        </style>
        \(math)</head>
        <body><article class="doc">\(body)</article></body>
        </html>
        """
    }

    func attributedDocument() -> NSAttributedString? {
        let html = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: "Times New Roman", serif; font-size: 12pt; line-height: 1.4; }
        h1 { font-size: 20pt; } h2 { font-size: 16pt; } h3 { font-size: 13pt; }
        code, pre { font-family: Menlo, monospace; font-size: 10pt; }
        blockquote { margin-left: 18pt; color: #444; }
        th, td { border: 1px solid #888; padding: 3pt 6pt; }
        mark { background: #ffe066; }
        </style></head><body>\(renderHTML())</body></html>
        """
        return NSAttributedString(
            html: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
    }

    func wordData() -> Data? {
        guard let document = attributedDocument() else { return nil }
        return try? document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }

    func chooseDestination(_ pathExtension: String, _ completion: @escaping (URL) -> Void) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(exportTitle).\(pathExtension)"
        if let type = UTType(filenameExtension: pathExtension) { panel.allowedContentTypes = [type] }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    func printPreview(savingTo url: URL?, completion: (() -> Void)? = nil) {
        guard let window else { return }
        refreshPreview(force: true) { [weak self] _ in
            guard let self else { return }
            let info = NSPrintInfo(dictionary: NSPrintInfo.shared.dictionary() as! [NSPrintInfo.AttributeKey: Any])
            info.topMargin = 56
            info.bottomMargin = 56
            info.leftMargin = 64
            info.rightMargin = 64
            info.isVerticallyCentered = false
            if let url {
                info.jobDisposition = .save
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            }
            let operation = self.preview.webView.printOperation(with: info)
            operation.showsPrintPanel = url == nil
            operation.showsProgressPanel = url == nil
            operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            completion?()
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        chooseDestination("html") { [weak self] url in
            try? self?.standaloneHTML().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        chooseDestination("pdf") { [weak self] url in self?.printPreview(savingTo: url) }
    }

    @objc func exportWord(_ sender: Any?) {
        chooseDestination("docx") { [weak self] url in
            try? self?.wordData()?.write(to: url)
        }
    }

    @objc func exportMarkdown(_ sender: Any?) {
        chooseDestination("md") { [weak self] url in
            try? self?.editor.storage.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func copyHTML(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(renderHTML(), forType: .string)
    }

    @objc func copyFormatted(_ sender: Any?) {
        guard let document = attributedDocument() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([document])
    }

    @objc func printDocument(_ sender: Any?) { printPreview(savingTo: nil) }

    @objc func printPlainText(_ sender: Any?) {
        guard let window else { return }
        let page = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        page.textStorage?.setAttributedString(NSAttributedString(
            string: editor.storage.string,
            attributes: [.font: Theme.font(family: "mono").withSize(11), .foregroundColor: NSColor.black]))
        NSPrintOperation(view: page).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
