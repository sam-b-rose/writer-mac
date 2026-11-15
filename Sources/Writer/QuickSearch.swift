import AppKit
import WriterCore

final class QuickSearchController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Choice {
        case open(URL)
        case create(String)
    }

    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
        styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    let field = NSSearchField()
    let table = NSTableView()
    let library: LibraryViewController
    let completion: (Choice?) -> Void
    var results: [LibraryNode] = []
    weak var parent: NSWindow?

    init(library: LibraryViewController, completion: @escaping (Choice?) -> Void) {
        self.library = library
        self.completion = completion
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        field.placeholderString = "Search library, or type a new title"
        field.font = .systemFont(ofSize: 16)
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(confirm)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(field)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            field.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        panel.contentView = content
        search()
    }

    func present(on window: NSWindow) {
        parent = window
        window.beginSheet(panel, completionHandler: nil)
        panel.makeFirstResponder(field)
    }

    func search() {
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty
            ? library.files.sorted { $0.modified > $1.modified }
            : library.index.search(query, in: library.root)
        let lower = query.lowercased()
        results = Array(matches.sorted { a, b in
            a.title.lowercased().contains(lower) && !b.title.lowercased().contains(lower)
        }.prefix(60))
        table.reloadData()
        if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func finish(_ choice: Choice?) {
        parent?.endSheet(panel)
        completion(choice)
    }

    @objc func confirm() {
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if results.indices.contains(table.selectedRow) {
            finish(.open(results[table.selectedRow].url))
        } else if !name.isEmpty {
            finish(.create(name))
        }
    }

    func controlTextDidChange(_ notification: Notification) { search() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !results.isEmpty else { return true }
            let step = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = min(max(table.selectedRow + step, 0), results.count - 1)
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            confirm()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(nil)
            return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let node = results[row]
        let folder = node.url.deletingLastPathComponent().path.replacingOccurrences(of: Settings.shared.libraryPath, with: "")
        let title = NSMutableAttributedString(string: node.title, attributes: [.font: NSFont.systemFont(ofSize: 13.5)])
        if !folder.isEmpty {
            title.append(NSAttributedString(string: "   " + folder.dropFirst(), attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        cell.textField?.attributedStringValue = title
        return cell
    }
}
