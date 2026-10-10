import SwiftUI

/// 挿入先の入力欄を囲む枠線。窓いっぱいに内側へ描く。
struct InsertionTargetOutlineView: View {
    /// 線の太さ。
    static let lineWidth: CGFloat = 3
    /// 線の角の丸み。
    static let cornerRadius: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .strokeBorder(Color.accentColor, lineWidth: Self.lineWidth)
            .accessibilityHidden(true)
    }
}
