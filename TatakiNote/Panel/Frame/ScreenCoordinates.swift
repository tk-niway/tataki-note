import AppKit

/// 左上が原点の座標(Quartz・アクセシビリティ)と、左下が原点の座標(Cocoa)の変換。
enum ScreenCoordinates {
    /// 左上が原点の枠を、左下が原点の枠に直す。
    static func cocoaRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// 左下が原点の点を、左上が原点の点に直す。
    static func topLeftPoint(fromCocoa point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// メインの画面(`NSScreen.screens.first`)の枠。画面が無ければ nil。
    static var primaryScreenFrame: CGRect? {
        NSScreen.screens.first?.frame
    }
}
