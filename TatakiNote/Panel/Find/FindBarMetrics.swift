import CoreGraphics

/// 検索バーの寸法。
enum FindBarMetrics {
    static let findRowHeight: CGFloat = 36
    static let replaceRowHeight: CGFloat = 28

    /// 検索バーの高さ。出ていなければ 0。
    static func height(isVisible: Bool, isReplaceShown: Bool) -> CGFloat {
        guard isVisible else { return 0 }
        return findRowHeight + (isReplaceShown ? replaceRowHeight : 0)
    }
}
