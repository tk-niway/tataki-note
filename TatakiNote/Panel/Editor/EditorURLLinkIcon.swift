import AppKit

/// 畳んだ URL の先頭に描くリンクのアイコン。
enum EditorURLLinkIcon {
    /// SF Symbols の名前。
    static let symbolName = "link"

    /// 入力欄のフォントサイズでのアイコンの画像(色を付けたもの)。作れなければ nil。
    static func image(pointSize: CGFloat, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return base.withSymbolConfiguration(configuration)
    }

    /// 入力欄のフォントサイズでのアイコンの大きさ。作れなければ nil。
    static func size(pointSize: CGFloat) -> CGSize? {
        image(pointSize: pointSize, color: .labelColor)?.size
    }

    /// アイコンの後ろのすき間。
    static func gap(pointSize: CGFloat) -> CGFloat {
        pointSize * 0.25
    }

    /// アイコンを描く矩形(入力欄の座標、上が小さい)。左端は `minX`、上下の中央は文字の高さの中央。
    static func rect(minX: CGFloat, baselineY: CGFloat, ascender: CGFloat, descender: CGFloat, size: CGSize) -> CGRect {
        let centerY = baselineY - (ascender + descender) / 2
        return CGRect(x: minX, y: centerY - size.height / 2, width: size.width, height: size.height)
    }
}
