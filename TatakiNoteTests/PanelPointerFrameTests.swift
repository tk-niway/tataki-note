import CoreGraphics
import Testing
@testable import TatakiNote

struct PanelPointerFrameTests {
    private let frame = CGRect(x: 100, y: 100, width: 520, height: 340)
    private let minimum = CGSize(width: 320, height: 160)
    private let start = CGPoint(x: 300, y: 300)

    private var anchor: PanelPointerAnchor {
        PanelPointerAnchor(frame: frame, pointer: start, isSidebarOpen: false)
    }

    private func point(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: start.x + dx, y: start.y + dy)
    }

    private func moved(dx: CGFloat, dy: CGFloat, limit: CGFloat? = 1000) -> CGRect {
        PanelPointerFrame.moved(anchor: anchor, pointer: point(dx: dx, dy: dy), screenTopLimit: limit)
    }

    private func resized(_ corner: PanelResizeCorner, dx: CGFloat, dy: CGFloat, limit: CGFloat? = 1000) -> CGRect {
        PanelPointerFrame.resized(
            anchor: anchor,
            corner: corner,
            pointer: point(dx: dx, dy: dy),
            minimumSize: minimum,
            screenTopLimit: limit
        )
    }

    @Test("AC-5: 動きが 0 なら枠は変わらない")
    func movedWithoutDelta() {
        #expect(moved(dx: 0, dy: 0) == frame)
    }

    @Test("AC-5: カーソルの動きと同じだけ枠が動き、大きさは変わらない")
    func movedByDelta() {
        #expect(moved(dx: 30, dy: -20) == CGRect(x: 130, y: 80, width: 520, height: 340))
    }

    @Test("AC-5: 左右・下は画面の外へ出せる")
    func movedOutsideLeftAndBottom() {
        #expect(moved(dx: -5000, dy: 0).origin.x == -4900)
        #expect(moved(dx: 0, dy: -5000).origin.y == -4900)
    }

    @Test("AC-9: 上端は限度を越えない")
    func movedStopsAtTopLimit() {
        let result = moved(dx: 10, dy: 700)
        #expect(result.origin.y == 660)
        #expect(result.maxY == 1000)
        #expect(result.origin.x == 110)
    }

    @Test("AC-9: 画面が無いときは上端を制限しない")
    func movedWithoutScreen() {
        #expect(moved(dx: 0, dy: 700, limit: nil).origin.y == 800)
    }

    @Test("AC-9: 始めた時点で画面の上端を越えていれば、起点の上端まで")
    func topLimitKeepsAnchorTop() {
        let tall = CGRect(x: 100, y: 760, width: 520, height: 340)
        #expect(PanelPointerFrame.topLimit(screenTopLimit: 1000, anchorFrame: tall) == 1100)
        #expect(PanelPointerFrame.topLimit(screenTopLimit: 1000, anchorFrame: frame) == 1000)
        #expect(PanelPointerFrame.topLimit(screenTopLimit: nil, anchorFrame: tall) == nil)
    }

    @Test("AC-9: 始めた時点で越えていても、動かさなければ跳ばない")
    func movedFromAboveLimitDoesNotJump() {
        let tall = CGRect(x: 100, y: 760, width: 520, height: 340)
        let anchor = PanelPointerAnchor(frame: tall, pointer: start, isSidebarOpen: false)
        let result = PanelPointerFrame.moved(anchor: anchor, pointer: start, screenTopLimit: 1000)
        #expect(result == tall)
    }

    @Test("AC-6: 右上の角を動かすと左下は止まる")
    func resizedTopRight() {
        #expect(resized(.topRight, dx: 40, dy: 30) == CGRect(x: 100, y: 100, width: 560, height: 370))
    }

    @Test("AC-6: 左下の角を動かすと右上は止まる")
    func resizedBottomLeft() {
        let result = resized(.bottomLeft, dx: 40, dy: 30)
        #expect(result == CGRect(x: 140, y: 130, width: 480, height: 310))
        #expect(result.maxX == frame.maxX)
        #expect(result.maxY == frame.maxY)
    }

    @Test("AC-6: 右下の角を動かすと左上は止まる")
    func resizedBottomRight() {
        let result = resized(.bottomRight, dx: 40, dy: -30)
        #expect(result == CGRect(x: 100, y: 70, width: 560, height: 370))
        #expect(result.minX == frame.minX)
        #expect(result.maxY == frame.maxY)
    }

    @Test("AC-6: 左上の角を動かすと右下は止まる")
    func resizedTopLeft() {
        let result = resized(.topLeft, dx: -40, dy: 30)
        #expect(result == CGRect(x: 60, y: 100, width: 560, height: 370))
        #expect(result.maxX == frame.maxX)
        #expect(result.minY == frame.minY)
    }

    @Test("AC-6: 最小の幅で止まり、反対の右端は動かない")
    func resizedStopsAtMinimumWidth() {
        let result = resized(.topLeft, dx: 400, dy: 0)
        #expect(result.width == 320)
        #expect(result.origin.x == 300)
        #expect(result.maxX == frame.maxX)
    }

    @Test("AC-6: 最小の高さで止まり、反対の上端は動かない")
    func resizedStopsAtMinimumHeight() {
        let result = resized(.bottomRight, dx: 0, dy: 300)
        #expect(result.height == 160)
        #expect(result.origin.y == 280)
        #expect(result.maxY == frame.maxY)
    }

    @Test("AC-6: 右上で最小の高さまで縮めても下端は動かない")
    func resizedTopStopsAtMinimumHeight() {
        let result = resized(.topRight, dx: 0, dy: -300)
        #expect(result.height == 160)
        #expect(result.origin.y == frame.minY)
    }

    @Test("AC-6: 本文より広い最小の大きさ(サイドバーが開いている)でも止まる")
    func resizedStopsAtSidebarMinimum() {
        let result = PanelPointerFrame.resized(
            anchor: anchor,
            corner: .bottomRight,
            pointer: point(dx: -400, dy: 0),
            minimumSize: SidebarLayout.minimumWindowSize(isSidebarOpen: true),
            screenTopLimit: 1000
        )
        #expect(result.width == 540)
    }

    @Test("AC-9: サイズ変更の上の角も画面の上端を越えない")
    func resizedTopStopsAtTopLimit() {
        let result = resized(.topRight, dx: 0, dy: 700)
        #expect(result.maxY == 1000)
        #expect(result.height == 900)
    }

    @Test("AC-9: サイズ変更で画面が無ければ上端を制限しない")
    func resizedWithoutScreen() {
        #expect(resized(.topRight, dx: 0, dy: 700, limit: nil).maxY == 1140)
    }

    @Test("AC-6: 区画の角を点から決める")
    func nearestCorners() {
        #expect(PanelResizeCorner.nearest(to: CGPoint(x: 110, y: 430), in: frame) == .topLeft)
        #expect(PanelResizeCorner.nearest(to: CGPoint(x: 610, y: 430), in: frame) == .topRight)
        #expect(PanelResizeCorner.nearest(to: CGPoint(x: 110, y: 110), in: frame) == .bottomLeft)
        #expect(PanelResizeCorner.nearest(to: CGPoint(x: 610, y: 110), in: frame) == .bottomRight)
    }

    @Test("AC-6: 真ん中ちょうどは右上")
    func nearestCenter() {
        #expect(PanelResizeCorner.nearest(to: CGPoint(x: 360, y: 270), in: frame) == .topRight)
    }

    // MARK: screenTopLimit

    private let screens: [(frame: CGRect, visibleFrame: CGRect)] = [
        (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 0, y: 0, width: 1440, height: 875)),
        (CGRect(x: 1440, y: 0, width: 1920, height: 1080), CGRect(x: 1440, y: 0, width: 1920, height: 1055)),
    ]

    @Test("AC-9: 画面の中の点は、その画面の使える範囲の上端")
    func screenTopLimitInside() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 100, y: 100), screens: screens) == 875)
    }

    @Test("AC-9: 画面の上端ちょうどの点も、その画面の使える範囲の上端")
    func screenTopLimitOnTopEdge() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 100, y: 900), screens: screens) == 875)
    }

    @Test("AC-9: 画面どうしの境目の点は右の画面")
    func screenTopLimitOnSharedEdge() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 1440, y: 500), screens: screens) == 1055)
    }

    @Test("AC-9: 画面の右上の角ちょうどの点も、その画面")
    func screenTopLimitOnTopRightCorner() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 3360, y: 1080), screens: screens) == 1055)
    }

    @Test("AC-9: どの画面の外の点は nil")
    func screenTopLimitOutside() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 100, y: 2000), screens: screens) == nil)
    }

    @Test("AC-9: 画面の一覧が空なら nil")
    func screenTopLimitWithoutScreens() {
        #expect(PanelPointerFrame.screenTopLimit(at: CGPoint(x: 100, y: 100), screens: []) == nil)
    }
}
