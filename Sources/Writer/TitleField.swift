import AppKit

final class TitleField: NSTextField, NSTextFieldDelegate {
    var onRename: ((String) -> Bool)?
    var onFinish: (() -> Void)?
    private var original = ""
    private lazy var editingWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: 240)

    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        isSelectable = false
        alignment = .center
        font = .titleBarFont(ofSize: 0)
        lineBreakMode = .byTruncatingMiddle
        usesSingleLineMode = true
        focusRingType = .none
        toolTip = "Rename"
        delegate = self
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        guard !isEditable else { return super.mouseDown(with: event) }
        guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { return }
        if next.type == .leftMouseDragged { window?.performDrag(with: event) } else { beginEditing() }
    }

    func beginEditing() {
        original = stringValue
        isEditable = true
        editingWidth.isActive = true
        window?.makeFirstResponder(self)
    }

    private func endEditing() {
        isSelectable = false
        editingWidth.isActive = false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(cancelOperation(_:)) else { return false }
        abortEditing()
        stringValue = original
        endEditing()
        onFinish?()
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isEditable else { return }
        endEditing()
        let name = stringValue.trimmingCharacters(in: .whitespaces)
        if name == original || onRename?(name) != true { stringValue = original }
        if notification.userInfo?["NSTextMovement"] as? Int == NSTextMovement.return.rawValue { onFinish?() }
    }
}
