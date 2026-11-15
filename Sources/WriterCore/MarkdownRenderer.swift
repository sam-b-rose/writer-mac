import cmark_gfm
import cmark_gfm_extensions
import Foundation

public enum ContentBlock {
    case markdown(String)
    case image(source: String)
    case csv(String)
    case code(String, language: String)
}

public struct RenderOptions {
    public var hardBreaks = false
    public var smartPunctuation = false
    public var loadBlock: ((String) -> ContentBlock?)?

    public init() {}
}

public struct Heading {
    public let level: Int
    public let title: String
    public let id: String
}

public enum MarkdownRenderer {
    final class Context {
        var math: [(tex: String, display: Bool)] = []
        var code: [String] = []
    }

    static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    static let contentBlock = regex("^/([^\\s/\"][^\"\\n]*?)(?:[ \\t]+\"([^\"\\n]*)\")?[ \\t]*$")
    static let wikilink = regex("\\[\\[([^\\]|\\n]+)(?:\\|([^\\]\\n]+))?\\]\\]")
    static let highlight = regex("==(?=\\S)(.+?)(?<=\\S)==")
    static let pageBreak = regex("^\\+{3}[ \\t]*$")
    static let toc = regex("^\\{\\{TOC\\}\\}[ \\t]*$")
    static let codePlaceholder = regex("\u{E000}C(\\d+)\u{E001}")
    static let mathPlaceholder = regex("\u{E000}M(\\d+)\u{E001}")
    static let headingTag = try! NSRegularExpression(pattern: "<h([1-6])>([\\s\\S]*?)</h\\1>")
    static let anyTag = try! NSRegularExpression(pattern: "<[^>]+>")
    static let calloutStart = try! NSRegularExpression(
        pattern: "<blockquote>\\s*<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\][ \\t]*(?:<br ?/?>)?\\s*")

    static func replace(_ regex: NSRegularExpression, in text: String, _ transform: (NSTextCheckingResult, NSString) -> String) -> String {
        let source = text as NSString
        let out = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            out.replaceCharacters(in: match.range, with: transform(match, source))
        }
        return out as String
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, _ source: NSString) -> String? {
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : source.substring(with: range)
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func transformInline(_ chunk: String, _ context: Context) -> String {
        var text = replace(SyntaxScanner.code, in: chunk) { match, source in
            context.code.append(source.substring(with: match.range))
            return "\u{E000}C\(context.code.count - 1)\u{E001}"
        }
        text = replace(SyntaxScanner.math, in: text) { match, source in
            let raw = source.substring(with: match.range)
            let display = raw.hasPrefix("$$")
            let trim = display ? 2 : 1
            context.math.append((String(raw.dropFirst(trim).dropLast(trim)), display))
            return "\u{E000}M\(context.math.count - 1)\u{E001}"
        }
        text = replace(wikilink, in: text) { match, source in
            let target = group(match, 1, source)!.trimmingCharacters(in: .whitespaces)
            let label = group(match, 2, source) ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target
            return "[\(label)](writer://open/\(encoded))"
        }
        text = replace(highlight, in: text) { match, source in "<mark>\(group(match, 1, source)!)</mark>" }
        text = replace(pageBreak, in: text) { _, _ in "\n<div class=\"page-break\"></div>\n" }
        text = replace(toc, in: text) { _, _ in "\n<!--TOC-->\n" }
        return replace(codePlaceholder, in: text) { match, source in
            context.code[Int(group(match, 1, source)!)!]
        }
    }

    public static func csvRows(_ text: String) -> [[String]] {
        let firstLine = text.prefix { !$0.isNewline }
        let delimiter: Character = [",", ";", "\t"].max { a, b in
            firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count
        } ?? ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if quoted {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    static func tableMarkdown(csv: String) -> String {
        let rows = csvRows(csv)
        guard let width = rows.map(\.count).max(), width > 0 else { return "" }
        var table = MarkdownTable(rows: rows.count, columns: width)
        table.rows = rows.map { row in
            (row + Array(repeating: "", count: width - row.count)).map {
                $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            }
        }
        return table.render()
    }

    static func preprocess(_ markdown: String, _ options: RenderOptions, _ context: Context, depth: Int) -> String {
        var out: [String] = []
        var chunk: [String] = []
        var fence: String?
        let markdown = Frontmatter.strip(markdown)
        func flush() {
            if !chunk.isEmpty { out.append(transformInline(chunk.joined(separator: "\n"), context)) }
            chunk = []
        }
        for line in markdown.components(separatedBy: "\n") {
            if let marker = SyntaxScanner.isFence(line) {
                if fence == nil {
                    flush()
                    fence = marker
                } else if fence == marker {
                    fence = nil
                }
                out.append(line)
                continue
            }
            if fence != nil {
                out.append(line)
                continue
            }
            let lineRange = NSRange(location: 0, length: (line as NSString).length)
            if depth < 3, let load = options.loadBlock,
               let match = contentBlock.firstMatch(in: line, range: lineRange),
               let block = load(group(match, 1, line as NSString)!) {
                let title = group(match, 2, line as NSString)
                switch block {
                case .markdown(let inner):
                    flush()
                    out.append("\n" + preprocess(inner, options, context, depth: depth + 1) + "\n")
                case .image(let source):
                    flush()
                    let caption = title.map { "<figcaption>\(escape($0))</figcaption>" } ?? ""
                    out.append("\n<figure><img src=\"\(escape(source))\" alt=\"\(escape(title ?? ""))\">\(caption)</figure>\n")
                case .csv(let csv):
                    chunk.append("\n" + tableMarkdown(csv: csv) + "\n")
                case .code(let code, let language):
                    flush()
                    out.append("\n````\(language)\n\(code)\n````\n")
                }
                continue
            }
            chunk.append(line)
        }
        flush()
        return out.joined(separator: "\n")
    }

    static func cmark(_ markdown: String, _ options: RenderOptions) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        var flags: Int32 = (1 << 17) | (1 << 13)
        if options.hardBreaks { flags |= 1 << 2 }
        if options.smartPunctuation { flags |= 1 << 10 }
        guard let parser = cmark_parser_new(flags) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        let bytes = Array(markdown.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                cmark_parser_feed(parser, $0, buffer.count)
            }
        }
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let rendered = cmark_render_html(document, flags, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(rendered) }
        return String(cString: rendered)
    }

    static func slug(_ title: String, _ used: inout [String: Int]) -> String {
        var base = title.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        if base.isEmpty { base = "section" }
        let count = used[base, default: 0]
        used[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    static func postprocess(_ html: String, _ context: Context) -> String {
        var headings: [Heading] = []
        var used: [String: Int] = [:]
        var matches: [(NSRange, String)] = []
        let source = html as NSString
        for match in headingTag.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let level = Int(source.substring(with: match.range(at: 1)))!
            let inner = source.substring(with: match.range(at: 2))
            let title = anyTag.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length), withTemplate: "")
            let id = slug(title, &used)
            headings.append(Heading(level: level, title: title, id: id))
            matches.append((match.range, "<h\(level) id=\"\(id)\">\(inner)</h\(level)>"))
        }
        let mutable = NSMutableString(string: html)
        for (range, replacement) in matches.reversed() { mutable.replaceCharacters(in: range, with: replacement) }
        var out = mutable as String

        if out.contains("<!--TOC-->") {
            let top = headings.map(\.level).min() ?? 1
            let items = headings.map { "<li class=\"toc-\($0.level - top + 1)\"><a href=\"#\($0.id)\">\($0.title)</a></li>" }
            out = out.replacingOccurrences(of: "<!--TOC-->", with: "<nav class=\"toc\"><ul>\(items.joined())</ul></nav>")
        }
        out = replace(calloutStart, in: out) { match, source in
            let kind = group(match, 1, source)!
            return "<blockquote class=\"callout callout-\(kind.lowercased())\"><p class=\"callout-title\">\(kind.capitalized)</p><p>"
        }
        return replace(mathPlaceholder, in: out) { match, source in
            let item = context.math[Int(group(match, 1, source)!)!]
            return "<span class=\"math \(item.display ? "display" : "inline")\">\(escape(item.tex))</span>"
        }
    }

    public static func html(_ markdown: String, options: RenderOptions = RenderOptions()) -> String {
        let context = Context()
        let prepared = preprocess(markdown, options, context, depth: 0)
        return postprocess(cmark(prepared, options), context)
    }
}
