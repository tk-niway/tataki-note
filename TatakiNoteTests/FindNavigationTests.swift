import Foundation
import Testing
@testable import TatakiNote

struct FindNavigationTests {
    private static let matches = [
        NSRange(location: 2, length: 2),
        NSRange(location: 6, length: 2),
        NSRange(location: 10, length: 2),
    ]

    private static func match(_ location: Int) -> TextMatch {
        let range = NSRange(location: location, length: 1)
        return TextMatch(range: range, groups: [range])
    }

    @Test("AC-8: 次の一致は選択の後ろから探す")
    func nextAfterSelection() {
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 0, length: 0)) == 0)
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 4, length: 0)) == 1)
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 3, length: 4)) == 2)
    }

    @Test("AC-8: 選択が一致と同じなら次の一致へ進む")
    func nextFromCurrentMatch() {
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 2, length: 2)) == 1)
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 6, length: 2)) == 2)
    }

    @Test("AC-8: 次の一致は末尾を越えたら先頭へ折り返す")
    func nextWrapsToStart() {
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 10, length: 2)) == 0)
        #expect(FindNavigation.nextIndex(in: Self.matches, after: NSRange(location: 11, length: 0)) == 0)
    }

    @Test("AC-8: 前の一致は選択の前から探す")
    func previousBeforeSelection() {
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 7, length: 0)) == 1)
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 9, length: 0)) == 1)
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 11, length: 0)) == 2)
    }

    @Test("AC-8: 選択が一致と同じなら前の一致へ戻る")
    func previousFromCurrentMatch() {
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 10, length: 2)) == 1)
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 6, length: 2)) == 0)
    }

    @Test("AC-8: 前の一致は先頭を越えたら末尾へ折り返す")
    func previousWrapsToEnd() {
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 2, length: 2)) == 2)
        #expect(FindNavigation.previousIndex(in: Self.matches, before: NSRange(location: 0, length: 0)) == 2)
    }

    @Test("AC-8: 一致が無ければ行き先も無い")
    func noMatchesHaveNoTarget() {
        let selection = NSRange(location: 0, length: 0)
        #expect(FindNavigation.nextIndex(in: [], after: selection) == nil)
        #expect(FindNavigation.previousIndex(in: [], before: selection) == nil)
        #expect(FindNavigation.nearestIndex(in: [], from: 0) == nil)
        #expect(FindNavigation.currentIndex(in: [], selection: selection) == nil)
    }

    @Test("AC-8: 長さ 0 の一致でも、選択と同じなら次へ進む")
    func zeroLengthMatchAdvances() {
        let zeroLength = [NSRange(location: 0, length: 0), NSRange(location: 3, length: 0)]
        #expect(FindNavigation.nextIndex(in: zeroLength, after: NSRange(location: 0, length: 0)) == 1)
        #expect(FindNavigation.nextIndex(in: zeroLength, after: NSRange(location: 3, length: 0)) == 0)
        #expect(FindNavigation.previousIndex(in: zeroLength, before: NSRange(location: 3, length: 0)) == 0)
        #expect(FindNavigation.previousIndex(in: zeroLength, before: NSRange(location: 0, length: 0)) == 1)
    }

    @Test("AC-8: 一致が1つだけなら、その一致に折り返す")
    func singleMatchWraps() {
        let single = [NSRange(location: 4, length: 1)]
        #expect(FindNavigation.nextIndex(in: single, after: NSRange(location: 4, length: 1)) == 0)
        #expect(FindNavigation.previousIndex(in: single, before: NSRange(location: 4, length: 1)) == 0)
    }

    @Test("AC-8: 位置以降で最初の一致を選び、無ければ先頭の一致を選ぶ")
    func nearestMatch() {
        #expect(FindNavigation.nearestIndex(in: Self.matches, from: 0) == 0)
        #expect(FindNavigation.nearestIndex(in: Self.matches, from: 3) == 1)
        #expect(FindNavigation.nearestIndex(in: Self.matches, from: 6) == 1)
        #expect(FindNavigation.nearestIndex(in: Self.matches, from: 11) == 0)
    }

    @Test("AC-8: 選択とちょうど同じ範囲の一致だけが今の一致になる")
    func currentMatchNeedsExactRange() {
        #expect(FindNavigation.currentIndex(in: Self.matches, selection: NSRange(location: 6, length: 2)) == 1)
        #expect(FindNavigation.currentIndex(in: Self.matches, selection: NSRange(location: 6, length: 1)) == nil)
        #expect(FindNavigation.currentIndex(in: Self.matches, selection: NSRange(location: 5, length: 2)) == nil)
    }

    @Test("AC-9: 今の一致があれば「番号/件数」を出す")
    func countTextWithCurrentMatch() {
        let matches = (0..<12).map { Self.match($0) }
        let result = TextSearchResult.found(matches, isTruncated: false)
        #expect(FindNavigation.countText(for: result, currentIndex: 2) == "3/12")
        #expect(FindNavigation.countText(for: result, currentIndex: 0) == "1/12")
    }

    @Test("AC-9: 選択が一致でなければ「?/件数」を出す")
    func countTextWithoutCurrentMatch() {
        let matches = (0..<12).map { Self.match($0) }
        let result = TextSearchResult.found(matches, isTruncated: false)
        #expect(FindNavigation.countText(for: result, currentIndex: nil) == "?/12")
    }

    @Test("AC-9: 一致が無い・正規表現が正しくないときは「結果なし」を出す")
    func countTextWithoutResults() {
        #expect(FindNavigation.countText(for: .found([], isTruncated: false), currentIndex: nil) == "結果なし")
        #expect(FindNavigation.countText(for: .invalidPattern, currentIndex: nil) == "結果なし")
    }

    @Test("AC-9: 検索語が空なら何も出さない")
    func countTextWithoutQuery() {
        #expect(FindNavigation.countText(for: .noQuery, currentIndex: nil).isEmpty)
    }

    @Test("AC-9: 打ち切ったときは件数を「19999+」と出す")
    func countTextWhenTruncated() {
        let matches = (0..<TextSearch.matchLimit).map { Self.match($0) }
        let result = TextSearchResult.found(matches, isTruncated: true)
        #expect(FindNavigation.countText(for: result, currentIndex: nil) == "?/19999+")
        #expect(FindNavigation.countText(for: result, currentIndex: 4) == "5/19999+")
    }

    @Test("AC-9: 正規表現が正しくないときの知らせを出す")
    func invalidPatternMessageText() {
        #expect(FindNavigation.invalidPatternMessage == "正規表現が正しくありません")
    }

    @Test("AC-10: 1行の中の選択は検索語の種になる")
    func seedFromSingleLineSelection() {
        let text = "hello a.b world" as NSString
        #expect(FindNavigation.seed(selection: NSRange(location: 6, length: 3), in: text, isRegex: false) == "a.b")
    }

    @Test("AC-10: 正規表現がオンなら種をエスケープする")
    func seedIsEscapedForRegex() {
        let text = "hello a.b world" as NSString
        #expect(FindNavigation.seed(selection: NSRange(location: 6, length: 3), in: text, isRegex: true) == "a\\.b")
    }

    @Test("AC-10: 選択が空なら種にしない")
    func emptySelectionIsNotSeed() {
        let text = "hello" as NSString
        #expect(FindNavigation.seed(selection: NSRange(location: 0, length: 0), in: text, isRegex: false) == nil)
    }

    @Test("AC-10: 複数行の選択は種にしない")
    func multiLineSelectionIsNotSeed() {
        let text = "a\nb" as NSString
        #expect(FindNavigation.seed(selection: NSRange(location: 0, length: 3), in: text, isRegex: false) == nil)
        #expect(FindNavigation.seed(selection: NSRange(location: 0, length: 3), in: text, isRegex: true) == nil)
    }

    @Test("AC-10: 文章の外にはみ出した選択は種にしない")
    func outOfBoundsSelectionIsNotSeed() {
        let text = "abc" as NSString
        #expect(FindNavigation.seed(selection: NSRange(location: 2, length: 5), in: text, isRegex: false) == nil)
        #expect(FindNavigation.seed(selection: NSRange(location: NSNotFound, length: 0), in: text, isRegex: false) == nil)
    }
}
