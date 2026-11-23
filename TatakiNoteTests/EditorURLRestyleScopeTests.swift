import Foundation
import Testing
@testable import TatakiNote

struct EditorURLRestyleScopeTests {
    private func presentation(_ range: NSRange, folded: Bool) -> EditorURLPresentation {
        let url = EditorURL(range: range, text: "")
        guard folded else { return EditorURLPresentation(url: url, fold: nil) }
        let fold = EditorURLFold(
            schemeRange: NSRange(location: range.location, length: 8),
            middleRange: NSRange(location: range.location + 8, length: 20)
        )
        return EditorURLPresentation(url: url, fold: fold)
    }

    private let rangeA = NSRange(location: 10, length: 40)
    private let rangeB = NSRange(location: 60, length: 40)

    private func restyle(
        previous: [EditorURLPresentation],
        current: [EditorURLPresentation],
        redetected: NSRange? = nil,
        isWhole: Bool = false,
        textLength: Int = 100
    ) -> [NSRange] {
        EditorURLRestyleScope.restyleRanges(
            previous: previous,
            current: current,
            redetectedRange: redetected,
            isWhole: isWhole,
            textLength: textLength
        )
    }

    // MARK: - restyleRanges

    @Test("AC-4: 見え方も文章も変わらなければ付け直す範囲は空")
    func nothingChangedGivesNoRanges() {
        let both = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        #expect(restyle(previous: both, current: both).isEmpty)
    }

    @Test("AC-4: 見え方の変わった URL の範囲だけを付け直す")
    func changedPresentationIsRestyled() {
        let folded = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        let aOpen = [presentation(rangeA, folded: false), presentation(rangeB, folded: true)]
        #expect(restyle(previous: folded, current: aOpen) == [rangeA])

        let aOpenBFolded = aOpen
        let aFoldedBOpen = [presentation(rangeA, folded: true), presentation(rangeB, folded: false)]
        #expect(restyle(previous: aOpenBFolded, current: aFoldedBOpen) == [rangeA, rangeB])
    }

    @Test("AC-4: 探し直した範囲は付け直し、その中の URL は前回と比べない")
    func redetectedRangeIsRestyledAndItsUrlsAreNotCompared() {
        let both = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        #expect(restyle(previous: both, current: both, redetected: NSRange(location: 0, length: 9)) == [NSRange(location: 0, length: 9)])

        let inside = NSRange(location: 0, length: 55)
        let aOpen = [presentation(rangeA, folded: false), presentation(rangeB, folded: true)]
        #expect(restyle(previous: both, current: aOpen, redetected: inside) == [inside])
    }

    @Test("AC-4: 探し直した範囲の外で見え方が変わった URL は、接しない限り別の範囲のまま")
    func restyleRangesStaySeparateUnlessTouching() {
        let both = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        let aOpen = [presentation(rangeA, folded: false), presentation(rangeB, folded: true)]
        #expect(
            restyle(previous: both, current: aOpen, redetected: NSRange(location: 0, length: 9))
                == [NSRange(location: 0, length: 9), rangeA]
        )
        #expect(
            restyle(previous: both, current: aOpen, redetected: NSRange(location: 0, length: 10))
                == [NSRange(location: 0, length: 50)]
        )
    }

    @Test("AC-4: 探し直した範囲の外で、前回あって今回無い URL・今回だけにある URL の範囲も付け直す")
    func appearedAndDisappearedUrlsAreRestyled() {
        let onlyA = [presentation(rangeA, folded: true)]
        let onlyB = [presentation(rangeB, folded: true)]
        #expect(restyle(previous: onlyA, current: []) == [rangeA])
        #expect(restyle(previous: [], current: onlyB) == [rangeB])
        #expect(restyle(previous: onlyA, current: onlyB) == [rangeA, rangeB])
        #expect(restyle(previous: onlyA, current: [], redetected: NSRange(location: 0, length: 55)) == [NSRange(location: 0, length: 55)])
    }

    @Test("AC-4: 全体の付け直しのときは文書全体で、文章が空なら空")
    func wholeRestyleCoversTheDocument() {
        let both = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        #expect(restyle(previous: both, current: both, redetected: NSRange(location: 0, length: 100), isWhole: true) == [NSRange(location: 0, length: 100)])
        #expect(restyle(previous: [], current: [], redetected: NSRange(location: 0, length: 0), isWhole: true, textLength: 0).isEmpty)
        #expect(restyle(previous: [], current: [], redetected: NSRange(location: 0, length: 0), textLength: 0).isEmpty)
    }

    @Test("AC-4: 範囲は文章の長さに収める")
    func rangesAreClampedToTheTextLength() {
        let result = restyle(previous: [], current: [], redetected: NSRange(location: 90, length: 30))
        #expect(result == [NSRange(location: 90, length: 10)])
    }

    // MARK: - recolorRanges

    private func change(redetected: NSRange?, changeInLength: Int) -> EditorURLIndexChange {
        let edits = changeInLength == 0 && redetected == nil
            ? []
            : [EditorTextEdit(range: NSRange(location: 20, length: 1), changeInLength: changeInLength)]
        return EditorURLIndexChange(redetectedRange: redetected, edits: edits, isWhole: false)
    }

    @Test("AC-4: 色が文字と一緒に動くときは、色を付け直す範囲は付け直す範囲と同じ")
    func recolorEqualsRestyleWhenColorsFollowText() {
        let restyle = [NSRange(location: 20, length: 10)]
        let result = EditorURLRestyleScope.recolorRanges(
            restyleRanges: restyle,
            change: change(redetected: NSRange(location: 20, length: 10), changeInLength: 1),
            textLength: 100,
            colorsFollowText: true
        )
        #expect(result == restyle)
    }

    @Test("AC-4: 色が文字と一緒に動かず長さが変わったときは、探し直した範囲の始まりから文末までを足す")
    func recolorAddsTheTailWhenColorsDoNotFollowText() {
        let redetected = NSRange(location: 20, length: 10)
        let result = EditorURLRestyleScope.recolorRanges(
            restyleRanges: [NSRange(location: 20, length: 10)],
            change: change(redetected: redetected, changeInLength: -1),
            textLength: 100,
            colorsFollowText: false
        )
        #expect(result == [NSRange(location: 20, length: 80)])

        let withEarlier = EditorURLRestyleScope.recolorRanges(
            restyleRanges: [NSRange(location: 0, length: 5), NSRange(location: 20, length: 10)],
            change: change(redetected: redetected, changeInLength: 2),
            textLength: 100,
            colorsFollowText: false
        )
        #expect(withEarlier == [NSRange(location: 0, length: 5), NSRange(location: 20, length: 80)])
    }

    @Test("AC-4: 色が文字と一緒に動かなくても、長さが変わらない・探し直していないときは付け直す範囲のまま")
    func recolorIsUnchangedWithoutLengthChange() {
        let restyle = [NSRange(location: 20, length: 10)]
        let sameLength = EditorURLRestyleScope.recolorRanges(
            restyleRanges: restyle,
            change: change(redetected: NSRange(location: 20, length: 10), changeInLength: 0),
            textLength: 100,
            colorsFollowText: false
        )
        let notRedetected = EditorURLRestyleScope.recolorRanges(
            restyleRanges: restyle,
            change: EditorURLIndexChange(redetectedRange: nil, edits: [], isWhole: false),
            textLength: 100,
            colorsFollowText: false
        )
        #expect(sameLength == restyle)
        #expect(notRedetected == restyle)
    }

    // MARK: - shifted

    @Test("AC-4: 前回の見え方は、変更の後の位置へ URL と隠す範囲を同じだけ移す")
    func shiftedMovesUrlAndFoldRanges() throws {
        let previous = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        let insertion = EditorTextEdit(range: NSRange(location: 0, length: 3), changeInLength: 3)
        let result = EditorURLRestyleScope.shifted(previous, through: [insertion])

        #expect(result.map(\.url.range) == [NSRange(location: 13, length: 40), NSRange(location: 63, length: 40)])
        let fold = try #require(result[0].fold)
        #expect(fold.schemeRange == NSRange(location: 13, length: 8))
        #expect(fold.middleRange == NSRange(location: 21, length: 20))
        #expect(result[1].url.text == previous[1].url.text)
    }

    @Test("AC-4: 変更に重なる・接する URL は除き、ほかは移す")
    func shiftedDropsUrlsTouchedByTheEdit() {
        let previous = [presentation(rangeA, folded: true), presentation(rangeB, folded: true)]
        let inside = EditorTextEdit(range: NSRange(location: 20, length: 2), changeInLength: 1)
        #expect(EditorURLRestyleScope.shifted(previous, through: [inside]).map(\.url.range) == [NSRange(location: 61, length: 40)])

        let touching = EditorTextEdit(range: NSRange(location: 50, length: 1), changeInLength: 1)
        #expect(EditorURLRestyleScope.shifted(previous, through: [touching]).map(\.url.range) == [NSRange(location: 61, length: 40)])

        let deletion = EditorTextEdit(range: NSRange(location: 2, length: 0), changeInLength: -2)
        #expect(EditorURLRestyleScope.shifted(previous, through: [deletion]).map(\.url.range) == [NSRange(location: 8, length: 40), NSRange(location: 58, length: 40)])
    }

    @Test("AC-4: 変更が複数あるときは古い順に移し、変更が無ければそのまま")
    func shiftedAppliesEditsInOrder() {
        let previous = [presentation(rangeA, folded: true)]
        let edits = [
            EditorTextEdit(range: NSRange(location: 0, length: 3), changeInLength: 3),
            EditorTextEdit(range: NSRange(location: 0, length: 0), changeInLength: -1),
        ]
        #expect(EditorURLRestyleScope.shifted(previous, through: edits).map(\.url.range) == [NSRange(location: 12, length: 40)])
        #expect(EditorURLRestyleScope.shifted(previous, through: []) == previous)
    }
}
