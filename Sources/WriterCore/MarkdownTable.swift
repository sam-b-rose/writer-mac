import Foundation

public struct MarkdownTable {
    public enum Alignment { case none, left, center, right }

    public var rows: [[String]]
    public var alignments: [Alignment]

    public var columnCount: Int { alignments.count }

    public init(rows: Int, columns: Int) {
        self.rows = (0..<max(rows, 1)).map { _ in Array(repeating: "", count: max(columns, 1)) }
        alignments = Array(repeating: .none, count: max(columns, 1))
    }

    public init?(lines: [String]) {
        guard lines.count >= 2, Self.isDelimiter(lines[1]) else { return nil }
        alignments = Self.cells(of: lines[1]).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            default: return .none
            }
        }
        rows = ([lines[0]] + lines.dropFirst(2)).map(Self.cells(of:))
        let width = max(alignments.count, rows.map(\.count).max() ?? 0)
        alignments += Array(repeating: .none, count: width - alignments.count)
        rows = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    static let delimiter = try! NSRegularExpression(
        pattern: "^[ \\t]*\\|?[ \\t]*:?-+:?[ \\t]*(?:\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*$")

    static func isDelimiter(_ line: String) -> Bool {
        line.contains("-") && delimiter.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    static func pipeOffsets(_ line: String) -> [Int] {
        var offsets: [Int] = []
        var escaped = false
        for (index, unit) in line.utf16.enumerated() {
            if unit == 0x7C, !escaped { offsets.append(index) }
            escaped = unit == 0x5C && !escaped
        }
        return offsets
    }

    public static func cells(of line: String) -> [String] {
        let source = line as NSString
        var cuts = pipeOffsets(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var start = 0
        if trimmed.hasPrefix("|"), let first = cuts.first {
            start = first + 1
            cuts.removeFirst()
        }
        var end = source.length
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|"), let last = cuts.last, last >= start {
            end = last
            cuts.removeLast()
        }
        var cells: [String] = []
        for cut in cuts + [end] {
            cells.append(source.substring(with: NSRange(location: start, length: max(cut - start, 0))).trimmingCharacters(in: .whitespaces))
            start = cut + 1
        }
        return cells
    }

    public static func columnIndex(in line: String, at offset: Int) -> Int {
        let before = pipeOffsets(line).filter { $0 < offset }.count
        let leading = line.trimmingCharacters(in: .whitespaces).hasPrefix("|") ? 1 : 0
        return max(before - leading, 0)
    }

    var widths: [Int] {
        (0..<columnCount).map { column in max(3, rows.map { $0[column].count }.max() ?? 0) }
    }

    static func pad(_ text: String, _ width: Int, _ alignment: Alignment) -> String {
        let space = max(width - text.count, 0)
        switch alignment {
        case .right: return String(repeating: " ", count: space) + text
        case .center: return String(repeating: " ", count: space / 2) + text + String(repeating: " ", count: space - space / 2)
        default: return text + String(repeating: " ", count: space)
        }
    }

    public func render() -> String {
        let widths = widths
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { Self.pad($1, widths[$0], alignments[$0]) }.joined(separator: " | ") + " |"
        }
        let rule = alignments.enumerated().map { index, alignment -> String in
            let width = widths[index]
            switch alignment {
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            case .none: return String(repeating: "-", count: width)
            }
        }
        return ([line(rows[0]), "| " + rule.joined(separator: " | ") + " |"] + rows.dropFirst().map(line)).joined(separator: "\n")
    }

    public func offset(row: Int, column: Int) -> Int {
        let widths = widths
        let lineLength = widths.reduce(0, +) + 3 * columnCount + 1
        let lineIndex = row == 0 ? 0 : row + 1
        let column = min(max(column, 0), columnCount - 1)
        let cellStart = 2 + widths[..<column].reduce(0, +) + 3 * column
        let leading = rows[row][column].isEmpty ? 0 : (Self.pad(rows[row][column], widths[column], alignments[column]) as NSString).range(of: rows[row][column]).location
        return lineIndex * (lineLength + 1) + cellStart + leading + (rows[row][column] as NSString).length
    }

    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: columnCount), at: min(max(index, 1), rows.count))
    }

    public mutating func deleteRow(_ index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    public mutating func moveRow(_ index: Int, by delta: Int) -> Int {
        let target = index + delta
        guard index >= 1, target >= 1, rows.indices.contains(index), rows.indices.contains(target) else { return index }
        rows.swapAt(index, target)
        return target
    }

    public mutating func insertColumn(at index: Int) {
        let index = min(max(index, 0), columnCount)
        alignments.insert(.none, at: index)
        rows = rows.map { row in
            var row = row
            row.insert("", at: index)
            return row
        }
    }

    public mutating func deleteColumn(_ index: Int) {
        guard columnCount > 1, alignments.indices.contains(index) else { return }
        alignments.remove(at: index)
        rows = rows.map { row in
            var row = row
            row.remove(at: index)
            return row
        }
    }

    public mutating func moveColumn(_ index: Int, by delta: Int) -> Int {
        let target = index + delta
        guard alignments.indices.contains(index), alignments.indices.contains(target) else { return index }
        alignments.swapAt(index, target)
        rows = rows.map { row in
            var row = row
            row.swapAt(index, target)
            return row
        }
        return target
    }

    public mutating func sort(column: Int, ascending: Bool) {
        guard alignments.indices.contains(column) else { return }
        let body = rows.dropFirst().sorted { a, b in
            let order = a[column].compare(b[column], options: [.numeric, .caseInsensitive])
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        rows = [rows[0]] + body
    }

    public struct Location {
        public var range: NSRange
        public var table: MarkdownTable
        public var row: Int
        public var column: Int
    }

    public static func locate(in text: NSString, at location: Int) -> Location? {
        let location = min(max(location, 0), text.length)
        let current = text.lineRange(for: NSRange(location: location, length: 0))
        func isRow(_ range: NSRange) -> Bool { text.substring(with: range).contains("|") }
        guard isRow(current) else { return nil }
        var lines = [current]
        while let first = lines.first, first.location > 0 {
            let previous = text.lineRange(for: NSRange(location: first.location - 1, length: 0))
            guard isRow(previous) else { break }
            lines.insert(previous, at: 0)
        }
        while let last = lines.last, NSMaxRange(last) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(last), length: 0))
            guard isRow(next) else { break }
            lines.append(next)
        }
        let strings = lines.map { text.substring(with: $0).trimmingCharacters(in: .newlines) }
        guard let table = MarkdownTable(lines: strings),
              let lineIndex = lines.firstIndex(where: { NSLocationInRange(location, $0) || NSMaxRange($0) == location && $0 == lines.last! })
        else { return nil }
        var range = NSUnionRange(lines.first!, lines.last!)
        if text.substring(with: range).hasSuffix("\n") { range.length -= 1 }
        let column = min(columnIndex(in: strings[lineIndex], at: location - lines[lineIndex].location), table.columnCount - 1)
        return Location(range: range, table: table, row: lineIndex <= 1 ? 0 : lineIndex - 1, column: column)
    }
}
