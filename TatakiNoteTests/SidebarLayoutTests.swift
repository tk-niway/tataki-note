import CoreGraphics
import Testing
@testable import TatakiNote

@MainActor
struct SidebarLayoutTests {
    private let width = SidebarLayout.width
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("AC-27: サイドバーを開くと窓が幅だけ左へ広がり、本文の部分の位置と大きさ・高さと上下の位置は変わらない")
    func expandGrowsLeftAndKeepsBody() {
        let body = CGRect(x: 500, y: 300, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: visible)

        #expect(expanded == CGRect(x: 500 - width, y: 300, width: 520 + width, height: 340))
        #expect(expanded.maxX == body.maxX)
        #expect(expanded.minY == body.minY)
        #expect(expanded.height == body.height)
    }

    @Test("AC-27: 画面の左端で入らないときは、窓全体が右へずれて見える範囲の左端に揃う")
    func expandShiftsRightAtLeftEdge() {
        let body = CGRect(x: 40, y: 300, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: visible)

        #expect(expanded.minX == visible.minX)
        #expect(expanded.width == 520 + width)
        #expect(expanded.maxX == visible.minX + 520 + width)
    }

    @Test("AC-27: 見える範囲の左端が 0 でない画面(左のディスプレイの外側など)でも、その左端に揃う")
    func expandAlignsToVisibleOrigin() {
        let shifted = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let body = CGRect(x: -1900, y: 200, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: shifted)

        #expect(expanded.minX == shifted.minX)
        #expect(expanded.width == 520 + width)
    }

    @Test("AC-27: 見える範囲より広くなるときは見える範囲の幅に縮み、本文の部分が狭くなる")
    func expandShrinksToVisibleWidth() {
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 800)
        let body = CGRect(x: 40, y: 100, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: narrow)

        #expect(expanded.minX == 0)
        #expect(expanded.width == 600)
        #expect(expanded.width - width == 380)
    }

    @Test("AC-27: 本文の部分は最小の幅より狭くしない。見える範囲がそれより狭い画面では窓がはみ出す")
    func expandKeepsMinimumBodyWidth() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 800)
        let body = CGRect(x: 0, y: 100, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: tiny)

        #expect(expanded.width == PanelSizing.minimumSize.width + width)
        #expect(expanded.minX == 0)
    }

    @Test("AC-27: 右端が見える範囲を出るときは左へずらす")
    func expandShiftsLeftAtRightEdge() {
        let body = CGRect(x: 1000, y: 300, width: 520, height: 340)

        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: visible)

        #expect(expanded.maxX == visible.maxX)
        #expect(expanded.width == 520 + width)
    }

    @Test("AC-27: 閉じると窓の左側から幅だけ縮み、本文の部分は動かない")
    func collapseShrinksFromLeft() {
        let expanded = CGRect(x: 280, y: 300, width: 740, height: 340)

        let collapsed = SidebarLayout.collapsedFrame(expandedFrame: expanded)

        #expect(collapsed == CGRect(x: 280 + width, y: 300, width: 520, height: 340))
        #expect(collapsed.maxX == expanded.maxX)
    }

    @Test("AC-27: 開いて閉じると本文の枠は元と同じ。右へずらしたときは本文がずれたまま動かない")
    func openAndCloseRoundTrip() {
        let body = CGRect(x: 500, y: 300, width: 520, height: 340)
        let expanded = SidebarLayout.expandedFrame(bodyFrame: body, visibleFrame: visible)
        #expect(SidebarLayout.collapsedFrame(expandedFrame: expanded) == body)

        let nearEdge = CGRect(x: 40, y: 300, width: 520, height: 340)
        let shifted = SidebarLayout.expandedFrame(bodyFrame: nearEdge, visibleFrame: visible)
        let closed = SidebarLayout.collapsedFrame(expandedFrame: shifted)
        #expect(closed == CGRect(x: width, y: 300, width: 520, height: 340))
        #expect(closed.minX == shifted.minX + width)
    }

    @Test("AC-27: 窓の大きさから本文の部分の大きさを出す。開いていればサイドバーの幅を引き、閉じていれば変えない")
    func bodySizeSubtractsSidebarWidthOnlyWhenOpen() {
        let window = CGSize(width: 740, height: 340)

        #expect(SidebarLayout.bodySize(windowSize: window, isSidebarOpen: true) == CGSize(width: 520, height: 340))
        #expect(SidebarLayout.bodySize(windowSize: window, isSidebarOpen: false) == window)
    }

    @Test("AC-27: 窓の最小の幅は、開いている間だけサイドバーの幅だけ大きく、閉じているときは今の最小のまま")
    func minimumWindowSizeAddsSidebarWidthOnlyWhenOpen() {
        let minimum = PanelSizing.minimumSize

        #expect(SidebarLayout.minimumWindowSize(isSidebarOpen: false) == minimum)
        #expect(SidebarLayout.minimumWindowSize(isSidebarOpen: true) == CGSize(width: minimum.width + width, height: minimum.height))
    }

    @Test("AC-27: 閉じているときの既定の大きさ・最小の大きさは今と同じ(520×340・320×160)")
    func closedMetricsAreUnchanged() {
        #expect(PanelMetrics.defaultSize == CGSize(width: 520, height: 340))
        #expect(PanelMetrics.minimumSize == CGSize(width: 320, height: 160))
        #expect(SidebarLayout.width == 220)
    }
}
