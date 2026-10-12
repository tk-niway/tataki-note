import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelMetricsTests {
    @Test("AC-1: 下の帯は 40pt で、パネルの既定の大きさは 520×340 のまま")
    func statusBarHeightAndDefaultSize() {
        #expect(PanelMetrics.statusBarHeight == 40)
        #expect(PanelMetrics.defaultSize == CGSize(width: 520, height: 340))
        #expect(PanelSizing().baseSize == CGSize(width: 520, height: 340))
    }

    @Test("パネルの入力欄の余白は 11×4 で、上の帯は 28 のまま")
    func metricsKeepPreviousValues() {
        #expect(PanelMetrics.titleBarHeight == 28)
        #expect(PanelMetrics.textContainerInset == NSSize(width: 11, height: 4))
        #expect(PanelMetrics.titleBarHeight + 272 + PanelMetrics.statusBarHeight == PanelMetrics.defaultSize.height)
    }

    @Test("AC-14: 最小の大きさは 320×160、既定の大きさの上限は 4000×4000 で、既定の大きさの範囲は幅 320〜4000・高さ 160〜4000")
    func defaultSizeLimits() {
        #expect(PanelMetrics.minimumSize == CGSize(width: 320, height: 160))
        #expect(PanelMetrics.maximumDefaultSize == CGSize(width: 4000, height: 4000))
        #expect(PanelMetrics.defaultWidthRange == 320...4000)
        #expect(PanelMetrics.defaultHeightRange == 160...4000)
        #expect(PanelMetrics.defaultWidthRange.contains(Double(PanelMetrics.defaultSize.width)))
        #expect(PanelMetrics.defaultHeightRange.contains(Double(PanelMetrics.defaultSize.height)))
    }

    @Test("AC-14: 既定の大きさの幅は 320〜4000・高さは 160〜4000 に丸め、NaN・無限大は初期値(幅 520・高さ 340)")
    func clampsDefaultSize() {
        let widths: [(Double, Double)] = [
            (-100, 320), (0, 320), (100, 320), (319, 320), (320, 320), (600.5, 600.5), (800, 800),
            (4000, 4000), (4001, 4000), (5000, 4000),
            (.nan, 520), (.infinity, 520), (-.infinity, 520),
        ]
        for (width, expected) in widths {
            #expect(PanelMetrics.clampedDefaultWidth(width) == expected, "\(width)")
        }

        let heights: [(Double, Double)] = [
            (-100, 160), (0, 160), (50, 160), (159, 160), (160, 160), (250.5, 250.5), (500, 500),
            (4000, 4000), (4001, 4000), (5000, 4000),
            (.nan, 340), (.infinity, 340), (-.infinity, 340),
        ]
        for (height, expected) in heights {
            #expect(PanelMetrics.clampedDefaultHeight(height) == expected, "\(height)")
        }
    }
}
