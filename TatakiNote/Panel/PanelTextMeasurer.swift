import AppKit

/// パネルの入力欄に文章を並べたときの高さを測る(パネルの高さの自動の伸び縮みに使う)。
enum PanelTextMeasurer {
    static func textHeight(of text: String, font: NSFont, panelWidth: CGFloat) -> CGFloat {
        let inset = PanelMetrics.textContainerInset
        let textStorage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: max(panelWidth - 2 * inset.width, 0), height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let extraLineBottom = layoutManager.extraLineFragmentRect.maxY
        let singleLineHeight = layoutManager.defaultLineHeight(for: font)
        let contentHeight = max(usedHeight, extraLineBottom, singleLineHeight)
        return (contentHeight + 2 * inset.height).rounded(.up)
    }
}
