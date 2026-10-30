import CoreGraphics

/// 画面に出ているウィンドウ1つ。一覧は手前から順に並べる。
struct OnScreenWindow: Equatable {
    var processIdentifier: pid_t
    var layer: Int
    /// 左上が原点の枠。
    var bounds: CGRect
}

/// 挿入先の入力欄を囲む枠線の場所の決まり。
enum InsertionTargetOutlineGeometry {
    /// 枠線で囲む枠(左上が原点)。出さないときは nil。
    static func outlineRect(
        fieldFrame: CGRect,
        targetProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t,
        windows: [OnScreenWindow]
    ) -> CGRect? {
        guard fieldFrame.size.width > 0, fieldFrame.size.height > 0 else { return nil }
        let others = windows.filter { $0.processIdentifier != ownProcessIdentifier }
        let center = CGPoint(x: fieldFrame.midX, y: fieldFrame.midY)
        guard let fieldWindowIndex = others.firstIndex(where: {
            $0.processIdentifier == targetProcessIdentifier && $0.bounds.contains(center)
        }) else { return nil }

        let visible = fieldFrame.intersection(others[fieldWindowIndex].bounds)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }

        let isCovered = others[..<fieldWindowIndex].contains { window in
            guard window.processIdentifier != targetProcessIdentifier, window.layer == 0 else { return false }
            let overlap = window.bounds.intersection(visible)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0
        }
        return isCovered ? nil : visible
    }

    /// 枠線の窓の枠(左下が原点)。枠を `outset` だけ外側へ広げる。
    static func windowFrame(outlineRect: CGRect, primaryScreenHeight: CGFloat, outset: CGFloat) -> CGRect {
        ScreenCoordinates
            .cocoaRect(fromTopLeft: outlineRect, primaryScreenHeight: primaryScreenHeight)
            .insetBy(dx: -outset, dy: -outset)
    }
}
