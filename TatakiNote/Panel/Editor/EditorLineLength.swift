import CoreGraphics

/// 1行の長さの上限から、入力欄の左右の余白を決める。
enum EditorLineLength {
    /// 左右の余白の幅。上限なし・入力欄が上限より狭いときは基本の余白、広いときは左右が同じになる中央寄せの幅。
    static func horizontalInset(viewWidth: CGFloat, baseInset: CGFloat, maxContainerWidth: CGFloat?) -> CGFloat {
        guard let maxContainerWidth else { return baseInset }
        guard viewWidth - 2 * baseInset > maxContainerWidth else { return baseInset }
        return (viewWidth - maxContainerWidth) / 2
    }

    /// `horizontalInset` を整数の位置に切り捨てた幅。文章を置く幅が上限より狭くならない。
    static func alignedHorizontalInset(viewWidth: CGFloat, baseInset: CGFloat, maxContainerWidth: CGFloat?) -> CGFloat {
        horizontalInset(viewWidth: viewWidth, baseInset: baseInset, maxContainerWidth: maxContainerWidth).rounded(.down)
    }
}
