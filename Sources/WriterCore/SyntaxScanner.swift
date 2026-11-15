import Foundation

public enum SpanKind: Equatable {
    case markup, strong, emphasis, strike, code, codeBlock, link, wikilink, hashtag, highlight, math, footnote
    case heading(hang: Int)
    case hanging(indent: Int)
}

public struct Span {
    public let range: NSRange
    public let kind: SpanKind
}

public struct ScanResult {
    public var spans: [Span] = []
    public var codeBlocks: [NSRange] = []
}

struct SortedRanges {
    private(set) var ranges: [NSRange] = []

    mutating func insert(_ new: [NSRange]) {
        ranges = (ranges + new).sorted { $0.location < $1.location }
    }

    func intersects(_ range: NSRange) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(ranges[mid]) <= range.location { low = mid + 1 } else { high = mid }
        }
        return low < ranges.count && ranges[low].location < NSMaxRange(range)
    }
}

public enum SyntaxScanner {
    static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    static let heading = regex("^(#{1,6})(?:[ \\t]+\\S.*|[ \\t]*)$")
    static let quote = regex("^[ \\t]*(?:>[ \\t]?)+")
    static let list = regex("^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?")
    static let rule = regex("^[ \\t]*(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,}|\\+{3})[ \\t]*$")
    static let tableRow = regex("^[ \\t]*\\|.*$")
    static let tableDelimiter = regex("^[ \\t]*\\|?[ \\t]*:?-{3,}:?[ \\t]*(?:\\|[ \\t]*:?-{3,}:?[ \\t]*)*\\|?[ \\t]*$")
    static let pipe = regex("(?<!\\\\)\\|")
    static let callout = regex("\\[!(?:NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]")
    static let tocMarker = regex("^\\{\\{TOC\\}\\}[ \\t]*$")
    static let contentBlock = regex("^/[^\\s/].*$")

    static let code = regex("(`+)(?!`)(.+?)(?<!`)\\1(?!`)")
    static let math = regex("\\$\\$[\\s\\S]+?\\$\\$|(?<![\\\\$\\w])\\$(?=\\S)[^$\\n]+?(?<=\\S)\\$(?![\\w$])")
    static let link = regex("(!?\\[)([^\\]\\n]*)(\\]\\([^)\\n]*\\))")
    static let footnote = regex("\\[\\^[^\\]\\n]+\\]:?")
    static let wikilink = regex("(\\[\\[)([^\\]\\n]+)(\\]\\])")
    static let url = regex("(?<![(\\[<])https?://[^\\s<>)\\]]+")
    static let strong = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    static let emphasis = regex("(?<![*\\w\\\\])(\\*|_)(?![\\s*_])(.+?)(?<![\\s*_\\\\])\\1(?![*\\w])")
    static let strike = regex("(~~)(?=\\S)(.+?)(?<=\\S)~~")
    static let highlight = regex("(==)(?=\\S)(.+?)(?<=\\S)==")
    public static let hashtag = regex("(?<![\\p{L}\\p{N}_#&/\\]\\(])#(?!\\d+(?:[^\\p{L}\\p{N}_]|$))[\\p{L}\\p{N}_][\\p{L}\\p{N}_/-]*")

    static func isFence(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    public static func fencedBlocks(in text: NSString) -> (blocks: [NSRange], fences: [NSRange]) {
        var blocks: [NSRange] = []
        var fences: [NSRange] = []
        var open: (start: Int, marker: String)?
        var position = Frontmatter.range(in: text).map(NSMaxRange) ?? 0
        while position < text.length {
            let line = text.lineRange(for: NSRange(location: position, length: 0))
            if let marker = isFence(text.substring(with: line)) {
                if let current = open {
                    if current.marker == marker {
                        blocks.append(NSRange(location: current.start, length: NSMaxRange(line) - current.start))
                        fences.append(line)
                        open = nil
                    }
                } else {
                    open = (line.location, marker)
                    fences.append(line)
                }
            }
            position = NSMaxRange(line)
        }
        if let current = open {
            blocks.append(NSRange(location: current.start, length: text.length - current.start))
        }
        return (blocks, fences)
    }

    public static func scan(_ text: NSString) -> ScanResult {
        var result = ScanResult()
        let full = NSRange(location: 0, length: text.length)
        let (blocks, fences) = fencedBlocks(in: text)
        let frontmatter = Frontmatter.range(in: text).map { [$0] } ?? []
        result.codeBlocks = frontmatter + blocks
        var excluded = SortedRanges()
        excluded.insert(result.codeBlocks)
        result.spans += frontmatter.map { Span(range: $0, kind: .markup) }
        result.spans += blocks.map { Span(range: $0, kind: .codeBlock) }
        result.spans += fences.map { Span(range: $0, kind: .markup) }

        func each(_ regex: NSRegularExpression, in range: NSRange? = nil, _ body: (NSTextCheckingResult) -> Void) {
            for match in regex.matches(in: text as String, range: range ?? full) where !excluded.intersects(match.range) {
                body(match)
            }
        }
        func add(_ range: NSRange, _ kind: SpanKind) {
            if range.location != NSNotFound, range.length > 0 { result.spans.append(Span(range: range, kind: kind)) }
        }

        each(heading) { match in
            add(match.range, .heading(hang: match.range(at: 1).length + 1))
            add(match.range(at: 1), .markup)
        }
        each(quote) { match in
            add(text.lineRange(for: match.range), .hanging(indent: match.range.length))
            add(match.range, .markup)
        }
        each(list) { match in
            add(text.lineRange(for: match.range), .hanging(indent: match.range.length))
            add(match.range, .markup)
        }
        each(rule) { add($0.range, .markup) }
        each(tableDelimiter) { add($0.range, .markup) }
        each(tableRow) { row in each(pipe, in: row.range) { add($0.range, .markup) } }
        each(tocMarker) { add($0.range, .hashtag) }
        each(contentBlock) { add($0.range, .link) }

        var inlineCode: [NSRange] = []
        each(code) { match in
            add(match.range, .code)
            add(match.range(at: 1), .markup)
            add(NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length), .markup)
            inlineCode.append(match.range)
        }
        excluded.insert(inlineCode)
        each(callout) { add($0.range, .hashtag) }

        var literal: [NSRange] = []
        each(math) { match in
            add(match.range, .math)
            literal.append(match.range)
        }
        excluded.insert(literal)
        literal = []
        each(wikilink) { match in
            add(match.range(at: 1), .markup)
            add(match.range(at: 2), .wikilink)
            add(match.range(at: 3), .markup)
            literal.append(match.range)
        }
        each(footnote) { match in
            add(match.range, .footnote)
            literal.append(match.range)
        }
        excluded.insert(literal)
        literal = []
        each(link) { match in
            add(match.range(at: 1), .markup)
            add(match.range(at: 2), .link)
            add(match.range(at: 3), .markup)
            literal.append(match.range(at: 3))
        }
        excluded.insert(literal)
        literal = []
        each(url) { match in
            add(match.range, .link)
            literal.append(match.range)
        }
        excluded.insert(literal)

        func delimited(_ regex: NSRegularExpression, _ kind: SpanKind) {
            each(regex) { match in
                let width = match.range(at: 1).length
                add(match.range(at: 2), kind)
                add(NSRange(location: match.range.location, length: width), .markup)
                add(NSRange(location: NSMaxRange(match.range) - width, length: width), .markup)
            }
        }
        delimited(strong, .strong)
        delimited(emphasis, .emphasis)
        delimited(strike, .strike)
        delimited(highlight, .highlight)
        each(hashtag) { add($0.range, .hashtag) }
        return result
    }

    public static func hashtags(in text: String) -> Set<String> {
        let source = text as NSString
        var excluded = SortedRanges()
        excluded.insert(fencedBlocks(in: source).blocks)
        excluded.insert(Frontmatter.range(in: source).map { [$0] } ?? [])
        var tags: Set<String> = []
        for match in hashtag.matches(in: text, range: NSRange(location: 0, length: source.length))
        where !excluded.intersects(match.range) {
            tags.insert(String(source.substring(with: match.range).dropFirst()).lowercased())
        }
        return tags
    }

    public static func outline(_ text: NSString) -> [OutlineHeading] {
        scan(text).spans.compactMap { span in
            guard case .heading(let hang) = span.kind else { return nil }
            let title = text.substring(with: span.range).drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if title.isEmpty { return nil }
            return OutlineHeading(level: hang - 1, title: title, location: span.range.location)
        }
    }
}

public struct OutlineHeading: Equatable {
    public let level: Int
    public let title: String
    public let location: Int
}
