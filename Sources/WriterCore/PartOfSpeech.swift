import Foundation
import NaturalLanguage

public enum PartOfSpeech: String, CaseIterable {
    case adjectives, nouns, adverbs, verbs, conjunctions

    public var title: String { rawValue.capitalized }

    init?(_ tag: NLTag) {
        switch tag {
        case .adjective: self = .adjectives
        case .noun: self = .nouns
        case .adverb: self = .adverbs
        case .verb: self = .verbs
        case .conjunction: self = .conjunctions
        default: return nil
        }
    }
}

public final class PartOfSpeechTagger {
    private var cache: [String: [(NSRange, PartOfSpeech)]] = [:]
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])
    private static let mask = try! NSRegularExpression(pattern: "\\]\\([^)\\n]*\\)|`[^`\\n]*`|https?://\\S+|\\[\\[|\\]\\]")

    public init() {}

    public func tags(in paragraph: String) -> [(NSRange, PartOfSpeech)] {
        if let cached = cache[paragraph] { return cached }
        if cache.count > 4000 { cache.removeAll() }
        let source = NSMutableString(string: paragraph)
        for match in Self.mask.matches(in: paragraph, range: NSRange(location: 0, length: source.length)).reversed() {
            source.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
        }
        let masked = source as String
        var out: [(NSRange, PartOfSpeech)] = []
        tagger.string = masked
        tagger.enumerateTags(
            in: masked.startIndex..<masked.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if let tag, let kind = PartOfSpeech(tag) { out.append((NSRange(range, in: masked), kind)) }
            return true
        }
        cache[paragraph] = out
        return out
    }
}
