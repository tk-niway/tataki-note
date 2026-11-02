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

/// 窓の枠を検索バーの高さの差だけ変えた結果。
struct FindBarFrameChange: Equatable {
    var frame: CGRect
    var upwardShift: CGFloat
    var appliedDelta: CGFloat
}

/// 検索バーの高さに合わせた窓の枠の計算。座標は AppKit の画面座標(下が小さい)。
enum FindBarFrame {
    /// 窓の枠を delta だけ縦に変える。伸ばして画面の下端を越える分は上へずらし、それでも収まらない分は伸ばさない。
    static func resized(
        _ frame: CGRect,
        by delta: CGFloat,
        upwardShift: CGFloat,
        visibleFrame: CGRect
    ) -> FindBarFrameChange {
        if delta > 0 {
            return stretched(frame, by: delta, upwardShift: upwardShift, visibleFrame: visibleFrame)
        }
        if delta < 0 {
            return shrunk(frame, by: -delta, upwardShift: upwardShift)
        }
        return FindBarFrameChange(frame: frame, upwardShift: upwardShift, appliedDelta: 0)
    }

    /// 開くときの窓の大きさと、そのうち検索バーの分として伸ばした高さ。
    static func openingSize(
        bodySize: CGSize,
        barHeight: CGFloat,
        visibleFrame: CGRect
    ) -> (size: CGSize, appliedBarHeight: CGFloat) {
        let room = max(0, visibleFrame.height - bodySize.height)
        let applied = max(0, min(barHeight, room))
        return (CGSize(width: bodySize.width, height: bodySize.height + applied), applied)
    }

    /// 検索バーの分を足した最小の大きさ。
    static func minimumSize(_ base: CGSize, barHeight: CGFloat) -> CGSize {
        CGSize(width: base.width, height: base.height + max(0, barHeight))
    }

    private static func stretched(
        _ frame: CGRect,
        by delta: CGFloat,
        upwardShift: CGFloat,
        visibleFrame: CGRect
    ) -> FindBarFrameChange {
        let shortfall = min(delta, max(0, visibleFrame.minY - (frame.minY - delta)))
        let room = max(0, visibleFrame.maxY - frame.maxY)
        let shift = min(shortfall, room)
        let applied = delta - (shortfall - shift)
        let top = frame.maxY + shift
        let height = frame.height + applied
        return FindBarFrameChange(
            frame: CGRect(x: frame.minX, y: top - height, width: frame.width, height: height),
            upwardShift: upwardShift + shift,
            appliedDelta: applied
        )
    }

    private static func shrunk(
        _ frame: CGRect,
        by amount: CGFloat,
        upwardShift: CGFloat
    ) -> FindBarFrameChange {
        let restore = min(max(0, upwardShift), amount)
        let top = frame.maxY - restore
        let height = frame.height - amount
        return FindBarFrameChange(
            frame: CGRect(x: frame.minX, y: top - height, width: frame.width, height: height),
            upwardShift: upwardShift - restore,
            appliedDelta: -amount
        )
    }
}
