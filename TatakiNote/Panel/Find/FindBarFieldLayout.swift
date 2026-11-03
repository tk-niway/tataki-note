import CoreGraphics

/// 検索欄・置換欄の文字の置き方。
enum FindBarFieldLayout {
    /// 中身の高さの矩形を、rect の中で上下の余白が等しくなるように置く。中身が rect より高ければ rect のまま。
    static func verticallyCentered(_ rect: CGRect, contentHeight: CGFloat) -> CGRect {
        guard contentHeight < rect.height else { return rect }
        let content = max(0, contentHeight)
        return CGRect(
            x: rect.minX,
            y: rect.minY + (rect.height - content) / 2,
            width: rect.width,
            height: content
        )
    }
}
