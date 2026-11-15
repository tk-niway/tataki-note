import CoreGraphics
import Testing
@testable import TatakiNote

struct EditorLineLengthTests {
    @Test("AC-7: 入力欄が上限より広いときは左右に同じ幅の余白を取って中央に寄せる")
    func centersWhenViewIsWiderThanLimit() {
        #expect(EditorLineLength.horizontalInset(viewWidth: 400, baseInset: 10, maxContainerWidth: 300) == 50)
        #expect(EditorLineLength.horizontalInset(viewWidth: 321, baseInset: 10, maxContainerWidth: 300) == 10.5)
    }

    @Test("AC-15: 中央寄せの余白は、文章を置く幅が上限より狭くならない整数に切り捨てられ、寄せないときは変わらない")
    func alignedInsetIsWholePoints() {
        #expect(EditorLineLength.alignedHorizontalInset(viewWidth: 400, baseInset: 10, maxContainerWidth: 300) == 50)
        #expect(EditorLineLength.alignedHorizontalInset(viewWidth: 321, baseInset: 10, maxContainerWidth: 300) == 10)
        #expect(EditorLineLength.alignedHorizontalInset(viewWidth: 322, baseInset: 10, maxContainerWidth: 300) == 11)
        #expect(EditorLineLength.alignedHorizontalInset(viewWidth: 320, baseInset: 10, maxContainerWidth: 300) == 10)
        #expect(EditorLineLength.alignedHorizontalInset(viewWidth: 2000, baseInset: 10, maxContainerWidth: nil) == 10)
    }

    @Test("AC-7: 入力欄が上限と同じか狭いときは今と同じ左右の余白になる")
    func keepsBaseInsetWhenViewIsNotWiderThanLimit() {
        #expect(EditorLineLength.horizontalInset(viewWidth: 320, baseInset: 10, maxContainerWidth: 300) == 10)
        #expect(EditorLineLength.horizontalInset(viewWidth: 319, baseInset: 10, maxContainerWidth: 300) == 10)
        #expect(EditorLineLength.horizontalInset(viewWidth: 0, baseInset: 10, maxContainerWidth: 300) == 10)
    }

    @Test("AC-7: 上限なしのときは入力欄がどれだけ広くても今と同じ左右の余白になる")
    func keepsBaseInsetWithoutLimit() {
        #expect(EditorLineLength.horizontalInset(viewWidth: 2000, baseInset: 10, maxContainerWidth: nil) == 10)
        #expect(EditorLineLength.horizontalInset(viewWidth: 0, baseInset: 10, maxContainerWidth: nil) == 10)
    }
}
