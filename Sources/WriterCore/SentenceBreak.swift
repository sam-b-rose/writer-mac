import Foundation

public enum SentenceBreak {
    static let blockStart = try! NSRegularExpression(pattern: "^[ \\t]*(#{1,6}[ \\t]|[-*+][ \\t]|\\d+[.)][ \\t]|>|\\|)")
    static let ending = try! NSRegularExpression(pattern: "[.!?][\"'”’)\\]*_]*$")
    static let abbreviations: Set<String> = ["dr.", "mr.", "mrs.", "ms.", "vs.", "etc.", "e.g.", "i.e.", "cf.", "st.", "prof.", "no."]

    public static func shouldBreak(after line: String) -> Bool {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        guard blockStart.firstMatch(in: line, range: whole) == nil,
              let end = ending.firstMatch(in: line, range: whole) else { return false }
        let terminator = (line as NSString).substring(with: NSRange(location: end.range.location, length: 1))
        guard terminator == "." else { return true }
        let closers = CharacterSet(charactersIn: "\"'”’)]*_")
        let word = line.split(whereSeparator: \.isWhitespace).last.map { String($0).trimmingCharacters(in: closers) } ?? ""
        let letters = word.filter { $0 != "." }
        let isInitial = letters.count == 1 && letters.first?.isUppercase == true
        let isDotted = word.dropLast().contains(".")
        return !(abbreviations.contains(word.lowercased()) || isInitial || isDotted)
    }
}
