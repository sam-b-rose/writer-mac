import CryptoKit
import Foundation

public struct AuthorRange: Equatable {
    public var range: NSRange
    public var author: String

    public init(range: NSRange, author: String) {
        self.range = range
        self.author = author
    }
}

public enum Author {
    public static let ai = "&AI"
    public static let reference = "*Reference"

    public static func named(_ name: String) -> String { "@" + name }

    public static func displayName(_ key: String) -> String {
        String(key.dropFirst())
    }
}

public enum Annotations {
    static let separator = "\n\n---\nAnnotations: "
    static let terminator = "...\n"

    static func digest(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func join(body: String, ranges: [AuthorRange]) -> String {
        guard !ranges.isEmpty else { return body }
        var byAuthor: [String: [NSRange]] = [:]
        for item in ranges where item.range.length > 0 {
            byAuthor[item.author, default: []].append(item.range)
        }
        var out = body + separator + "0,\((body as NSString).length) SHA-256 \(digest(body))\n"
        for author in byAuthor.keys.sorted() {
            let list = byAuthor[author]!.sorted { $0.location < $1.location }
                .map { "\($0.location),\($0.length)" }
                .joined(separator: " ")
            out += "\(author): \(list)\n"
        }
        return out + terminator
    }

    public static func split(_ file: String) -> (body: String, ranges: [AuthorRange]) {
        guard let found = file.range(of: separator, options: .backwards) else { return (file, []) }
        let body = String(file[..<found.lowerBound])
        var lines = file[found.upperBound...].split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count >= 2, lines.last == "..." else { return (file, []) }
        lines.removeLast()
        let header = lines.removeFirst().split(separator: " ")
        guard header.count == 3, header[1] == "SHA-256" else { return (file, []) }
        guard header[2] == digest(body) else { return (body, []) }
        let length = (body as NSString).length
        var ranges: [AuthorRange] = []
        for line in lines {
            guard let colon = line.range(of: ": ") else { continue }
            let author = String(line[..<colon.lowerBound])
            for pair in line[colon.upperBound...].split(separator: " ") {
                let parts = pair.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 2, parts[0] >= 0, parts[1] > 0, parts[0] + parts[1] <= length else { continue }
                ranges.append(AuthorRange(range: NSRange(location: parts[0], length: parts[1]), author: author))
            }
        }
        return (body, ranges)
    }
}
