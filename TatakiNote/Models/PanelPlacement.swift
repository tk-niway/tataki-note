import CoreGraphics

/// 画面の枠と可視領域(メニューバーと Dock を除いた領域)。
struct ScreenGeometry: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
}

enum PanelPlacement {
    static func screenContainingMouse(_ location: CGPoint, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        let containing = screens.first { screen in
            let frame = screen.frame
            return frame.minX <= location.x && location.x < frame.maxX
                && frame.minY < location.y && location.y <= frame.maxY
        }
        return containing ?? screens.first
    }

    static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = (visibleFrame.minX + (visibleFrame.width - width) / 2).rounded()
        let y = (visibleFrame.minY + (visibleFrame.height - height) / 2).rounded()
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func screen(
        for mode: PanelScreen,
        screens: [ScreenGeometry],
        mouseLocation: CGPoint,
        targetWindowFrame: CGRect?
    ) -> ScreenGeometry? {
        switch mode {
        case .mouse:
            return screenContainingMouse(mouseLocation, in: screens)
        case .main:
            return screens.first
        case .targetWindow, .nearFocusedField:
            if let targetWindowFrame, let screen = screenWithLargestOverlap(with: targetWindowFrame, in: screens) {
                return screen
            }
            return screenContainingMouse(mouseLocation, in: screens)
        }
    }

    static func cocoaFrame(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    static func screenWithLargestOverlap(with rect: CGRect, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        var best: (screen: ScreenGeometry, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > 0 else { continue }
            if let current = best, area <= current.area { continue }
            best = (screen, area)
        }
        return best?.screen
    }
}
