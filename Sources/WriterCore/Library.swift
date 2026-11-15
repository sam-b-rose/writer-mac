import Foundation

public enum LibrarySort: String, CaseIterable {
    case name, modified

    public var title: String { self == .name ? "Name" : "Date Modified" }
}

public final class LibraryNode: NSObject {
    public let url: URL
    public let isFolder: Bool
    public let modified: Date
    public var children: [LibraryNode] = []

    init(url: URL, isFolder: Bool, modified: Date) {
        self.url = url
        self.isFolder = isFolder
        self.modified = modified
    }

    public var title: String {
        isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}

public final class LibraryIndex {
    public static let textExtensions: Set<String> = ["md", "markdown", "mdown", "txt", "text"]

    private var contents: [String: (Date, String)] = [:]

    public init() {}

    public func scan(_ root: URL, sort: LibrarySort, reversed: Bool = false) -> LibraryNode {
        let manager = FileManager.default
        func node(_ url: URL) -> LibraryNode? {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isFolder = values?.isDirectory ?? false
            guard isFolder || Self.textExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let item = LibraryNode(url: url, isFolder: isFolder, modified: values?.contentModificationDate ?? .distantPast)
            if isFolder {
                let entries = (try? manager.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
                item.children = entries.compactMap(node).sorted { first, second in
                    if first.isFolder != second.isFolder { return first.isFolder }
                    let (a, b) = reversed ? (second, first) : (first, second)
                    switch sort {
                    case .name: return a.title.localizedStandardCompare(b.title) == .orderedAscending
                    case .modified: return a.modified > b.modified
                    }
                }
            }
            return item
        }
        return node(root) ?? LibraryNode(url: root, isFolder: true, modified: .distantPast)
    }

    public func scan(_ roots: [URL], sort: LibrarySort, reversed: Bool = false) -> LibraryNode {
        let combined = LibraryNode(url: roots.first ?? URL(fileURLWithPath: "/"), isFolder: true, modified: .distantPast)
        combined.children = roots.map { scan($0, sort: sort, reversed: reversed) }
        return combined
    }

    public func files(in node: LibraryNode) -> [LibraryNode] {
        node.isFolder ? node.children.flatMap(files(in:)) : [node]
    }

    public func content(of node: LibraryNode) -> String {
        if let cached = contents[node.url.path], cached.0 == node.modified { return cached.1 }
        let size = (try? node.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let text = size < 2_000_000 ? Annotations.split((try? String(contentsOf: node.url, encoding: .utf8)) ?? "").body : ""
        contents[node.url.path] = (node.modified, text)
        return text
    }

    public func hashtags(in root: LibraryNode) -> [String: [LibraryNode]] {
        var tags: [String: [LibraryNode]] = [:]
        for file in files(in: root) {
            for tag in SyntaxScanner.hashtags(in: content(of: file)) { tags[tag, default: []].append(file) }
        }
        return tags
    }

    public func search(_ query: String, in root: LibraryNode) -> [LibraryNode] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        return files(in: root).filter { file in
            let text = content(of: file)
            let lower = text.lowercased()
            let name = file.title.lowercased()
            lazy var tags = SyntaxScanner.hashtags(in: text)
            return terms.allSatisfy { term in
                term.hasPrefix("#") && term.count > 1 ? tags.contains(String(term.dropFirst())) : name.contains(term) || lower.contains(term)
            }
        }.sorted { $0.modified > $1.modified }
    }

    public func find(named name: String, in root: LibraryNode) -> LibraryNode? {
        let wanted = name.lowercased()
        return files(in: root).first { $0.title.lowercased() == wanted || $0.url.lastPathComponent.lowercased() == wanted }
    }
}
