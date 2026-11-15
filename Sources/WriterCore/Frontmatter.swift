import Foundation

public enum Frontmatter {
    static let block = try! NSRegularExpression(pattern: "\\A---[ \\t]*\\r?\\n(?:[^\\n]*\\n)*?(?:---|\\.\\.\\.)[ \\t]*\\r?(?:\\n|\\z)")

    public static func range(in text: NSString) -> NSRange? {
        guard text.hasPrefix("---") else { return nil }
        return block.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))?.range
    }

    public static func strip(_ text: String) -> String {
        guard let range = range(in: text as NSString) else { return text }
        return (text as NSString).substring(from: NSMaxRange(range))
    }
}
