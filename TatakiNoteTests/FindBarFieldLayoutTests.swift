import CoreGraphics
import Testing
@testable import TatakiNote

struct FindBarFieldLayoutTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 24)

    @Test("AC-45: 中身が欄より低いときは、上下の余白が等しくなる位置に置き、x と幅は変えない")
    func centersShorterContent() {
        #expect(FindBarFieldLayout.verticallyCentered(rect, contentHeight: 15) == CGRect(x: 0, y: 4.5, width: 200, height: 15))
        #expect(FindBarFieldLayout.verticallyCentered(rect, contentHeight: 0) == CGRect(x: 0, y: 12, width: 200, height: 0))
        let shifted = CGRect(x: 6, y: 10, width: 120, height: 24)
        #expect(FindBarFieldLayout.verticallyCentered(shifted, contentHeight: 14) == CGRect(x: 6, y: 15, width: 120, height: 14))
    }

    @Test("AC-45: 中身が欄と同じか高いときは、欄のまま")
    func keepsRectWhenContentIsNotShorter() {
        #expect(FindBarFieldLayout.verticallyCentered(rect, contentHeight: 24) == rect)
        #expect(FindBarFieldLayout.verticallyCentered(rect, contentHeight: 30) == rect)
    }
}
