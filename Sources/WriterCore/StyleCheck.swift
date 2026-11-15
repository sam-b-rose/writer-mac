import Foundation

public enum StyleCategory: String, CaseIterable {
    case fillers, cliches, redundancies, custom

    public var title: String {
        switch self {
        case .fillers: return "Fillers"
        case .cliches: return "Clichés"
        case .redundancies: return "Redundancies"
        case .custom: return "Custom Patterns"
        }
    }
}

public struct StyleChecker {
    static let builtIn: [StyleCategory: [String]] = [
        .fillers: [
            "actually", "basically", "certainly", "definitely", "essentially", "extremely", "fairly", "frankly",
            "honestly", "hopefully", "just", "kind of", "literally", "mostly", "obviously", "perhaps", "pretty much",
            "quite", "rather", "really", "seriously", "simply", "somehow", "somewhat", "sort of", "surely",
            "totally", "truly", "utterly", "very", "virtually",
        ],
        .cliches: [
            "a perfect storm", "at the end of the day", "at this point in time", "avoid like the plague",
            "best of both worlds", "circle back", "deep dive", "few and far between", "game changer",
            "going forward", "in the nick of time", "in this day and age", "it goes without saying",
            "last but not least", "level playing field", "low-hanging fruit", "move the needle",
            "needle in a haystack", "only time will tell", "paradigm shift", "par for the course",
            "push the envelope", "think outside the box", "tip of the iceberg", "touch base", "win-win",
        ],
        .redundancies: [
            "absolutely essential", "added bonus", "advance planning", "basic fundamentals", "close proximity",
            "completely finished", "each and every", "end result", "final outcome", "free gift", "future plans",
            "join together", "new innovation", "past history", "period of time", "reason why", "repeat again",
            "revert back", "true facts", "unexpected surprise", "very unique",
        ],
    ]

    let patterns: [(StyleCategory, NSRegularExpression)]

    public init(enabled: Set<StyleCategory>, custom: [String]) {
        var lists = StyleChecker.builtIn
        lists[.custom] = custom
        patterns = StyleCategory.allCases.compactMap { category in
            guard enabled.contains(category), let phrases = lists[category], !phrases.isEmpty else { return nil }
            let alternatives = phrases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|")
            guard !alternatives.isEmpty,
                  let regex = try? NSRegularExpression(
                      pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])",
                      options: [.caseInsensitive]
                  ) else { return nil }
            return (category, regex)
        }
    }

    public var isEmpty: Bool { patterns.isEmpty }

    public func matches(in text: String) -> [(range: NSRange, category: StyleCategory)] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { category, regex in
            regex.matches(in: text, range: full).map { ($0.range, category) }
        }
    }

    public static func parseCustom(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
