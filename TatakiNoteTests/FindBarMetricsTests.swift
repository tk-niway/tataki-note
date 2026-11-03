import CoreGraphics
import Testing
@testable import TatakiNote

struct FindBarMetricsTests {
    @Test("AC-48: 検索バーの高さは、出ていなければ 0、出ていれば検索の行、置換の行まで出ていればその分を足した高さ")
    func barHeights() {
        #expect(FindBarMetrics.height(isVisible: false, isReplaceShown: false) == 0)
        #expect(FindBarMetrics.height(isVisible: false, isReplaceShown: true) == 0)
        #expect(FindBarMetrics.height(isVisible: true, isReplaceShown: false) == FindBarMetrics.findRowHeight)
        #expect(
            FindBarMetrics.height(isVisible: true, isReplaceShown: true)
                == FindBarMetrics.findRowHeight + FindBarMetrics.replaceRowHeight
        )
    }
}
