import CoreGraphics

/// サイドバーを開閉したときの窓の枠の計算。
enum SidebarLayout {
    static let width: CGFloat = 220

    /// 本文の部分の枠から、サイドバーを開いた窓の枠を決める。
    static func expandedFrame(
        bodyFrame: CGRect,
        visibleFrame: CGRect,
        width: CGFloat = SidebarLayout.width,
        minimumBodyWidth: CGFloat = PanelSizing.minimumSize.width
    ) -> CGRect {
        let fittedWidth = min(bodyFrame.width + width, visibleFrame.width)
        let windowWidth = max(fittedWidth, minimumBodyWidth + width)
        var originX = bodyFrame.minX - width
        if originX + windowWidth > visibleFrame.maxX {
            originX = visibleFrame.maxX - windowWidth
        }
        if originX < visibleFrame.minX {
            originX = visibleFrame.minX
        }
        return CGRect(x: originX, y: bodyFrame.minY, width: windowWidth, height: bodyFrame.height)
    }

    /// サイドバーを開いた窓の枠から、閉じた窓(本文の部分だけ)の枠を決める。
    static func collapsedFrame(expandedFrame: CGRect, width: CGFloat = SidebarLayout.width) -> CGRect {
        CGRect(
            x: expandedFrame.minX + width,
            y: expandedFrame.minY,
            width: expandedFrame.width - width,
            height: expandedFrame.height
        )
    }

    /// 窓の大きさから本文の部分の大きさを出す。開いていればサイドバーの幅を引く。
    static func bodySize(windowSize: CGSize, isSidebarOpen: Bool, width: CGFloat = SidebarLayout.width) -> CGSize {
        CGSize(width: windowSize.width - (isSidebarOpen ? width : 0), height: windowSize.height)
    }

    /// 窓の最小の大きさ。開いていれば本文の最小の幅にサイドバーの幅を足す。
    static func minimumWindowSize(isSidebarOpen: Bool, width: CGFloat = SidebarLayout.width) -> CGSize {
        let minimum = PanelSizing.minimumSize
        return CGSize(width: minimum.width + (isSidebarOpen ? width : 0), height: minimum.height)
    }
}
