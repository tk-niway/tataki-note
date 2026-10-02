import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelMetricsTests {
    @Test("AC-12: パネルの寸法は今までの値(初期の大きさ 520×340、タイトルバー 28、帯 28、入力欄の余白 11×4)")
    func metricsKeepPreviousValues() {
        #expect(PanelMetrics.defaultSize == CGSize(width: 520, height: 340))
        #expect(PanelMetrics.titleBarHeight == 28)
        #expect(PanelMetrics.statusBarHeight == 28)
        #expect(PanelMetrics.textContainerInset == NSSize(width: 11, height: 4))
        #expect(PanelMetrics.titleBarHeight + 284 + PanelMetrics.statusBarHeight == PanelMetrics.defaultSize.height)
        #expect(PanelSizing().baseSize == CGSize(width: 520, height: 340))
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
