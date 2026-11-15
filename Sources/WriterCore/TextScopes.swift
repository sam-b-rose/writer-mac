import Foundation
import NaturalLanguage

public enum TextScopes {
    static func isBlank(_ text: NSString, _ range: NSRange) -> Bool {
        text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func paragraph(in text: NSString, at location: Int) -> NSRange {
        let location = min(max(location, 0), text.length)
        var range = text.lineRange(for: NSRange(location: location, length: 0))
        if isBlank(text, range) { return range }
        while range.location > 0 {
            let previous = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            if isBlank(text, previous) { break }
            range = NSUnionRange(previous, range)
        }
        while NSMaxRange(range) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            if isBlank(text, next) { break }
            range = NSUnionRange(range, next)
        }
        return range
    }

    public static func sentence(in text: NSString, at location: Int) -> NSRange {
        let paragraph = paragraph(in: text, at: location)
        let string = text.substring(with: paragraph)
        let offset = location - paragraph.location
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = string
        var result = paragraph
        for token in tokenizer.tokens(for: string.startIndex..<string.endIndex) {
            let local = NSRange(token, in: string)
            result = NSRange(location: paragraph.location + local.location, length: local.length)
            if offset < NSMaxRange(local) { break }
        }
        return result
    }
}
