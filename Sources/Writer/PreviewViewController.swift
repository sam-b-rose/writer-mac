import AppKit
import UniformTypeIdentifiers
import WebKit

final class ResourceHandler: NSObject, WKURLSchemeHandler {
    static let scriptExtensions: Set<String> = ["js", "mjs", "html", "htm", "xhtml", "svg"]

    func resolve(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "bundle":
            return Bundle.main.resourceURL?.appendingPathComponent(parts[1])
        case "user":
            return Settings.templatesDirectory.appendingPathComponent(parts[1])
        case "file":
            let file = URL(fileURLWithPath: "/" + parts[1])
            return Self.scriptExtensions.contains(file.pathExtension.lowercased()) ? nil : file
        default:
            return nil
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let file = resolve(url), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class PreviewViewController: NSViewController, WKNavigationDelegate {
    static let root = "writer://app/bundle/"
    static let shell = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src writer:; style-src writer: 'unsafe-inline'; img-src writer: https: http: data:; font-src writer: data:; media-src writer: https:">
    <base id="base" href="\(root)">
    <link rel="stylesheet" href="\(root)katex/katex.min.css">
    <link rel="stylesheet" href="\(root)Templates/base.css">
    <link rel="stylesheet" id="template" href="\(root)Templates/duo.css">
    <script src="\(root)katex/katex.min.js"></script>
    <script src="\(root)preview.js"></script>
    </head>
    <body><article id="doc" class="doc"></article></body>
    </html>
    """

    let webView: WKWebView
    var onOpenWikilink: ((String) -> Void)?

    private var ready = false
    private var pending: (html: String, base: String, completion: ((Int) -> Void)?)?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(ResourceHandler(), forURLScheme: "writer")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.shell, baseURL: URL(string: Self.root))
        webView.translatesAutoresizingMaskIntoConstraints = false
        let container = BackgroundView(frame: webView.frame)
        container.wantsLayer = true
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    static func templateHref(_ name: String) -> String {
        if Settings.builtInTemplates.contains(name) { return root + "Templates/\(name.lowercased()).css" }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "writer://app/user/\(encoded).css"
    }

    static func fileHref(_ url: URL) -> String {
        "writer://app/file" + (url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)
    }

    func update(html: String, documentURL: URL?, completion: ((Int) -> Void)? = nil) {
        let base = documentURL.map { Self.fileHref($0.deletingLastPathComponent()) + "/" } ?? Self.root
        pending = (html, base, completion)
        flush()
    }

    private func flush() {
        guard ready, let job = pending else { return }
        pending = nil
        let arguments = [job.html, job.base, Self.templateHref(Settings.shared.template)]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("writerUpdate.apply(null, \(json))") { result, _ in
            job.completion?(result as? Int ?? -1)
        }
    }

    func hideUntilRedrawn() {
        webView.alphaValue = 0
        let script = """
        const frame = () => new Promise(r => requestAnimationFrame(r))
        for (let i = 0; i < 30 && Math.abs(innerWidth - width) > 1; i++) await frame()
        await frame()
        await frame()
        """
        webView.callAsyncJavaScript(script, arguments: ["width": webView.bounds.width], in: nil, in: .page) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self?.webView.animator().alphaValue = 1
            }
        }
    }

    func scroll(to ratio: CGFloat) {
        guard ready else { return }
        webView.evaluateJavaScript("writerScroll(\(Double(ratio)))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        flush()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
            return
        }
        decisionHandler(.cancel)
        if url.scheme == "writer", url.host == "open" {
            onOpenWikilink?(String(url.path.dropFirst()))
        } else if url.scheme == "writer", let fragment = url.fragment {
            let id = fragment.replacingOccurrences(of: "'", with: "")
            webView.evaluateJavaScript("writerReveal('\(id)')", completionHandler: nil)
        } else if ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
}
