import Foundation
import NaturalLanguage

public enum StatKind: String, CaseIterable {
    case words, characters, charactersNoSpaces, sentences, paragraphs, tasks, reading, speaking

    public var title: String {
        switch self {
        case .words: return "Words"
        case .characters: return "Characters"
        case .charactersNoSpaces: return "Characters Without Spaces"
        case .sentences: return "Sentences"
        case .paragraphs: return "Paragraphs"
        case .tasks: return "Tasks"
        case .reading: return "Reading Time"
        case .speaking: return "Speaking Time"
        }
    }
}

public enum Stats {
    static let strip: [(NSRegularExpression, String)] = [
        ("^#{1,6}[ \\t]+", ""),
        ("^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?", ""),
        ("^[ \\t]*(?:>[ \\t]?)+", ""),
        ("!?\\[([^\\]\\n]*)\\]\\([^)\\n]*\\)", "$1"),
        ("[*_`~|]", ""),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.anchorsMatchLines]), $0.1) }

    static let word = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’-][\\p{L}\\p{N}]+)*")
    static let task = try! NSRegularExpression(pattern: "^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+\\[([ xX])\\]", options: [.anchorsMatchLines])

    static func plain(_ text: String) -> String {
        var out = Frontmatter.strip(text)
        for (regex, template) in strip {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: template)
        }
        return out
    }

    static func wordCount(_ text: String) -> Int {
        word.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.joined(separator: "\n") }
    }

    static func sentenceCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        return paragraphs(text).reduce(0) { sum, paragraph in
            tokenizer.string = paragraph
            return sum + tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex).count
        }
    }

    static func duration(words: Int, perMinute: Double) -> String {
        let seconds = Int((Double(words) / perMinute * 60).rounded())
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = Int((Double(seconds) / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    public static func count(_ kind: StatKind, in raw: String) -> Int {
        switch kind {
        case .tasks:
            return task.numberOfMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length))
        case .words, .reading, .speaking:
            return wordCount(plain(raw))
        case .characters:
            return plain(raw).filter { !$0.isNewline }.count
        case .charactersNoSpaces:
            return plain(raw).filter { !$0.isWhitespace }.count
        case .sentences:
            return sentenceCount(plain(raw))
        case .paragraphs:
            return paragraphs(plain(raw)).count
        }
    }

    public static func format(_ kind: StatKind, document: String, selection: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = { (n: Int) in formatter.string(from: NSNumber(value: n)) ?? "\(n)" }
        switch kind {
        case .reading:
            return duration(words: count(.words, in: selection.isEmpty ? document : selection), perMinute: 238) + " Reading"
        case .speaking:
            return duration(words: count(.words, in: selection.isEmpty ? document : selection), perMinute: 150) + " Speaking"
        case .tasks:
            let done = task.matches(in: document, range: NSRange(location: 0, length: (document as NSString).length))
                .filter { (document as NSString).substring(with: $0.range(at: 1)) != " " }.count
            return "\(number(done)) of \(number(count(.tasks, in: document))) Tasks"
        default:
            let total = count(kind, in: document)
            let unit: String
            switch kind {
            case .words: unit = total == 1 ? "Word" : "Words"
            case .sentences: unit = total == 1 ? "Sentence" : "Sentences"
            case .paragraphs: unit = total == 1 ? "Paragraph" : "Paragraphs"
            default: unit = total == 1 ? "Character" : "Characters"
            }
            if !selection.isEmpty { return "\(number(count(kind, in: selection))) of \(number(total)) \(unit)" }
            return "\(number(total)) \(unit)"
        }
    }
}
