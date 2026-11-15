import AppKit

final class FindBarScrollView: NSScrollView {
    private let findBarMargin: CGFloat = 8
    private var restingTopInset: CGFloat = 0

    override func tile() {
        super.tile()
        guard let bar = findBarView, isFindBarVisible else {
            restingTopInset = contentView.contentInsets.top
            return
        }
        let barHeight = bar.frame.height
        let width = min(bounds.width - findBarMargin * 2, Theme.characterWidth * 64)
        bar.frame = NSRect(
            x: ((bounds.width - width) / 2).rounded(),
            y: safeAreaInsets.top + findBarMargin,
            width: width,
            height: barHeight
        )
        styleFloating(bar)
        if let scroller = verticalScroller {
            scroller.frame = NSRect(x: scroller.frame.minX, y: scroller.frame.minY - barHeight, width: scroller.frame.width, height: scroller.frame.height + barHeight)
        }
        let textTop = (documentView as? NSTextView)?.textContainerInset.height ?? 0
        var insets = contentView.contentInsets
        insets.top = max(restingTopInset, bar.frame.maxY + findBarMargin - textTop)
        if !NSEdgeInsetsEqual(contentView.contentInsets, insets) { contentView.contentInsets = insets }
    }

    private func styleFloating(_ bar: NSView) {
        bar.wantsLayer = true
        guard let layer = bar.layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = Theme.background.cgColor
            layer.borderColor = NSColor.separatorColor.cgColor
        }
        layer.borderWidth = 1
        layer.cornerRadius = 10
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: -2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if isFindBarVisible { tile() }
    }
}
