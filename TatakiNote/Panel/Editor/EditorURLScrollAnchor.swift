import CoreGraphics

/// 畳む・開くで高さが変わっても、カーソルの行の画面上の位置を保つスクロールの位置を決める。
enum EditorURLScrollAnchor {
    /// カーソルの行の上端の差だけずらし、スクロールできる範囲に収めた縦の位置。
    static func adjustedOriginY(
        caretMinYBefore: CGFloat, caretMinYAfter: CGFloat,
        currentOriginY: CGFloat, documentHeight: CGFloat, visibleHeight: CGFloat
    ) -> CGFloat {
        let delta = caretMinYAfter - caretMinYBefore
        guard delta != 0 else { return currentOriginY }
        let upper = max(0, documentHeight - visibleHeight)
        return min(max(currentOriginY + delta, 0), upper)
    }
}
