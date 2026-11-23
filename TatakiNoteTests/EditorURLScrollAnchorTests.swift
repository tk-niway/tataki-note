import CoreGraphics
import Testing
@testable import TatakiNote

struct EditorURLScrollAnchorTests {
    private func adjusted(
        before: CGFloat, after: CGFloat, origin: CGFloat, document: CGFloat, visible: CGFloat
    ) -> CGFloat {
        EditorURLScrollAnchor.adjustedOriginY(
            caretMinYBefore: before, caretMinYAfter: after,
            currentOriginY: origin, documentHeight: document, visibleHeight: visible
        )
    }

    @Test("AC-4: カーソルの行の上端が動かなければ、スクロールの位置はそのまま")
    func zeroDeltaKeepsOrigin() {
        #expect(adjusted(before: 200, after: 200, origin: 80, document: 1000, visible: 300) == 80)
    }

    @Test("AC-4: 上端が下へ動いたぶん、スクロールの位置を下げる")
    func positiveDeltaScrollsDown() {
        #expect(adjusted(before: 200, after: 230, origin: 80, document: 1000, visible: 300) == 110)
    }

    @Test("AC-4: 上端が上へ動いたぶん、スクロールの位置を上げる")
    func negativeDeltaScrollsUp() {
        #expect(adjusted(before: 230, after: 200, origin: 80, document: 1000, visible: 300) == 50)
    }

    @Test("AC-4: 先頭より上・末尾より下には行かない")
    func clampsToScrollableRange() {
        #expect(adjusted(before: 200, after: 100, origin: 40, document: 1000, visible: 300) == 0)
        #expect(adjusted(before: 200, after: 900, origin: 600, document: 1000, visible: 300) == 700)
    }

    @Test("AC-4: 文章が表示の高さより短いときは 0")
    func shortDocumentIsZero() {
        #expect(adjusted(before: 20, after: 60, origin: 0, document: 200, visible: 300) == 0)
        #expect(adjusted(before: 60, after: 20, origin: 10, document: 200, visible: 300) == 0)
    }
}
