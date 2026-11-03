import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class FindModelFixture {
    let model = FindModel()
    let editor: FakeFindEditor

    init(_ marked: String) {
        editor = FakeFindEditor(marked)
        model.editor = { [editor] in editor }
        editor.onTextChange = { [model] in model.textDidChange() }
        editor.onSelectionChange = { [model] in model.selectionDidChange() }
    }

    func open(_ query: String, regex: Bool = false) {
        if regex { model.toggle(.regex) }
        model.open(revealsReplace: false, movesFocus: false, seed: query)
    }
}

@MainActor
struct FindModelTests {
    @Test("AC-23: 開くと数え直し、選択の位置から最も近い一致を選んで見せる")
    func openSelectsNearestMatch() {
        let fixture = FindModelFixture("foo bar| foo baz foo")
        fixture.open("foo")

        #expect(fixture.model.matches == [
            NSRange(location: 0, length: 3), NSRange(location: 8, length: 3), NSRange(location: 16, length: 3),
        ])
        #expect(fixture.editor.revealed == [NSRange(location: 8, length: 3)])
        #expect(fixture.model.currentIndex == 1)
        #expect(fixture.model.countText == "2/3")
    }

    @Test("AC-23: 末尾より後ろに一致が無ければ先頭の一致を選ぶ")
    func wrapsToFirstMatch() {
        let fixture = FindModelFixture("foo bar foo|")
        fixture.open("foo")

        #expect(fixture.editor.revealed == [NSRange(location: 0, length: 3)])
        #expect(fixture.model.countText == "1/2")
    }

    @Test("AC-23: 検索語を変えると数え直し、そのときの選択に近い一致を選ぶ")
    func queryChangeResearches() {
        let fixture = FindModelFixture("foo bar| foo baz")
        fixture.open("foo")
        #expect(fixture.editor.findSelection == NSRange(location: 8, length: 3))

        fixture.model.query = "baz"
        #expect(fixture.model.matches == [NSRange(location: 12, length: 3)])
        #expect(fixture.editor.findSelection == NSRange(location: 12, length: 3))
        #expect(fixture.model.countText == "1/1")

        fixture.model.query = "zzz"
        #expect(fixture.model.matches.isEmpty)
        #expect(fixture.model.currentIndex == nil)
        #expect(fixture.model.countText == FindNavigation.countText(for: .found([], isTruncated: false), currentIndex: nil))
    }

    @Test("AC-23: オプションを切り替えると数え直す")
    func optionToggleResearches() {
        let fixture = FindModelFixture("|Foo foo FOO")
        fixture.open("foo")
        #expect(fixture.model.matches.count == 3)

        fixture.model.toggle(.caseSensitive)
        #expect(fixture.model.options.isCaseSensitive)
        #expect(fixture.model.matches == [NSRange(location: 4, length: 3)])
        #expect(fixture.editor.findSelection == NSRange(location: 4, length: 3))

        fixture.model.toggle(.caseSensitive)
        #expect(fixture.model.matches.count == 3)
    }

    @Test("AC-23: 検索バーが出ていなければ数え直さず、入力欄にも触れない")
    func doesNothingWhileBarIsHidden() {
        let fixture = FindModelFixture("|foo foo")
        fixture.model.query = "foo"
        fixture.model.toggle(.wholeWord)

        #expect(fixture.model.matches.isEmpty)
        #expect(fixture.editor.revealed.isEmpty)
        #expect(fixture.editor.highlightCalls.isEmpty)
    }

    @Test("AC-23: 正規表現が正しくなければ一致なしで、知らせの文を出す。検索バーの高さは置換の行の有無で変わる")
    func invalidPatternAndBarHeight() {
        let fixture = FindModelFixture("|a(b")
        fixture.model.toggle(.regex)
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "(")

        #expect(fixture.model.isPatternInvalid)
        #expect(fixture.model.errorMessage == FindNavigation.invalidPatternMessage)
        #expect(fixture.model.matches.isEmpty)
        #expect(fixture.model.barHeight == FindBarMetrics.height(isVisible: true, isReplaceShown: false))

        fixture.model.toggleReplace()
        #expect(fixture.model.barHeight == FindBarMetrics.height(isVisible: true, isReplaceShown: true))

        fixture.model.query = "a"
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.model.isPatternInvalid == false)

        fixture.model.close()
        #expect(fixture.model.barHeight == 0)
    }

    @Test("AC-23: 開くときのフォーカスの要求は movesFocus が true のときだけ。閉じると当てていない要求は捨てる")
    func focusRequests() {
        let fixture = FindModelFixture("|foo")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: nil)
        #expect(fixture.model.hasPendingFocus(for: .find) == false)

        fixture.model.close()
        fixture.model.open(revealsReplace: false, movesFocus: true, seed: nil)
        #expect(fixture.model.hasPendingFocus(for: .find))
        #expect(fixture.model.hasPendingFocus(for: .replace) == false)

        fixture.model.didApplyFocus()
        #expect(fixture.model.hasPendingFocus(for: .find) == false)

        fixture.model.requestFocus(.replace)
        #expect(fixture.model.hasPendingFocus(for: .replace))
        fixture.model.close()
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: nil)
        #expect(fixture.model.hasPendingFocus(for: .replace) == false)
    }

    @Test("AC-24: 一致はすべてハイライトされ、今の一致だけ別の印になり、閉じると消える")
    func highlightsMatchesAndClearsOnClose() throws {
        let fixture = FindModelFixture("foo bar| foo baz")
        fixture.open("foo")

        let shown = try #require(fixture.editor.lastHighlights)
        #expect(shown.ranges == [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        #expect(shown.current == NSRange(location: 8, length: 3))

        fixture.editor.findSelection = NSRange(location: 5, length: 0)
        fixture.model.selectionDidChange()
        let unselected = try #require(fixture.editor.lastHighlights)
        #expect(unselected.ranges.count == 2)
        #expect(unselected.current == nil)
        #expect(fixture.model.countText == "?/2")

        fixture.model.close()
        let cleared = try #require(fixture.editor.lastHighlights)
        #expect(cleared.ranges.isEmpty)
        #expect(cleared.current == nil)
        #expect(fixture.model.query == "foo")
    }

    @Test("AC-25: 文章が変わると、検索語とオプションはそのままで、選択を動かさずに数え直す")
    func textChangeResearchesWithoutMovingSelection() {
        let fixture = FindModelFixture("foo| bar")
        fixture.model.toggle(.caseSensitive)
        fixture.open("foo")
        #expect(fixture.model.matches.count == 1)
        fixture.editor.findSelection = NSRange(location: 3, length: 0)
        let revealedBefore = fixture.editor.revealed.count

        fixture.editor.findText = "foo bar Foo foo foo"
        fixture.model.textDidChange()

        #expect(fixture.model.query == "foo")
        #expect(fixture.model.options.isCaseSensitive)
        #expect(fixture.model.matches == [
            NSRange(location: 0, length: 3), NSRange(location: 12, length: 3), NSRange(location: 16, length: 3),
        ])
        #expect(fixture.editor.revealed.count == revealedBefore)
        #expect(fixture.editor.findSelection == NSRange(location: 3, length: 0))
        #expect(fixture.model.currentIndex == nil)
        #expect(fixture.model.countText == "?/3")
    }

    @Test("AC-25: 文章が変わったとき、検索バーが出ていなければ何もしない")
    func textChangeWhileHiddenDoesNothing() {
        let fixture = FindModelFixture("|foo")
        fixture.model.textDidChange()
        #expect(fixture.model.matches.isEmpty)
        #expect(fixture.editor.highlightCalls.isEmpty)
    }

    @Test("AC-26: 選択が一致なら置き換えて次の一致へ進む")
    func replaceOneReplacesAndAdvances() {
        let fixture = FindModelFixture("|foo bar foo baz foo")
        fixture.open("foo")
        fixture.model.replacement = "X"

        fixture.model.replaceOne()
        #expect(fixture.editor.replaceCalls.count == 1)
        #expect(fixture.editor.replaceCalls[0].edits == [FindEdit(range: NSRange(location: 0, length: 3), replacement: "X")])
        #expect(fixture.editor.findText == "X bar foo baz foo")
        #expect(fixture.editor.findSelection == NSRange(location: 6, length: 3))
        #expect(fixture.model.countText == "1/2")

        fixture.model.replaceOne()
        #expect(fixture.editor.findText == "X bar X baz foo")
        #expect(fixture.editor.findSelection == NSRange(location: 12, length: 3))

        fixture.model.replaceOne()
        #expect(fixture.editor.findText == "X bar X baz X")
        #expect(fixture.model.matches.isEmpty)
        #expect(fixture.editor.findSelection == NSRange(location: 13, length: 0))
    }

    @Test("AC-26: 選択が一致でなければ置き換えずに次の一致へ移る")
    func replaceOneMovesWhenSelectionIsNotMatch() {
        let fixture = FindModelFixture("foo b|ar foo")
        fixture.open("foo")
        fixture.editor.findSelection = NSRange(location: 5, length: 0)
        fixture.model.replacement = "X"

        fixture.model.replaceOne()
        #expect(fixture.editor.replaceCalls.isEmpty)
        #expect(fixture.editor.findText == "foo bar foo")
        #expect(fixture.editor.findSelection == NSRange(location: 8, length: 3))
    }

    @Test("AC-26: 正規表現では置換語のキャプチャと大文字小文字の保持を使って置き換える")
    func replaceOneUsesCaptureAndPreserveCase() {
        let regex = FindModelFixture("|hello world")
        regex.open("(\\w+) (\\w+)", regex: true)
        regex.model.replacement = "$2 $1"
        regex.model.replaceOne()
        #expect(regex.editor.findText == "world hello")

        let preserved = FindModelFixture("|Foo foo")
        preserved.model.toggle(.preserveCase)
        preserved.open("foo")
        preserved.model.replacement = "bar"
        preserved.model.replaceOne()
        #expect(preserved.editor.findText == "Bar foo")
    }

    @Test("AC-27: すべて置換は、19,999 件を超えても全部を1回の置き換えで入れ替え、最後の置換の直後を選ぶ")
    func replaceAllBeyondLimit() {
        let fixture = FindModelFixture("|" + String(repeating: "a ", count: 20_000))
        fixture.open("a")
        #expect(fixture.model.isTruncated)
        fixture.model.replacement = "bb"

        fixture.model.replaceAll()
        #expect(fixture.editor.replaceCalls.count == 1)
        #expect(fixture.editor.replaceCalls[0].edits.count == 20_000)
        #expect(fixture.editor.findText == String(repeating: "bb ", count: 20_000))
        #expect(fixture.editor.findSelection == NSRange(location: 59_999, length: 0))
        #expect(fixture.model.matches.isEmpty)
    }

    @Test("AC-27: すべて置換のあと、置換語を含む検索語なら置換後の文章で数え直す")
    func replaceAllResearches() {
        let fixture = FindModelFixture("|foo bar foo")
        fixture.open("foo")
        fixture.model.replacement = "foofoo"

        fixture.model.replaceAll()
        #expect(fixture.editor.findText == "foofoo bar foofoo")
        #expect(fixture.model.matches.count == 4)
        #expect(fixture.editor.findSelection == NSRange(location: 17, length: 0))
    }

    @Test("AC-27: 一致が無ければすべて置換をしても文章は変わらない")
    func replaceAllWithoutMatchDoesNothing() {
        let fixture = FindModelFixture("|foo bar")
        fixture.open("zzz")
        fixture.model.replaceAll()
        #expect(fixture.editor.replaceCalls.isEmpty)
        #expect(fixture.editor.findText == "foo bar")
    }

    @Test("AC-28: 検索語が空なら、次・前・置換を押しても文章も選択も変わらない")
    func emptyQueryDoesNothing() {
        let fixture = FindModelFixture("foo b|ar foo")
        fixture.model.open(revealsReplace: true, movesFocus: false, seed: nil)
        fixture.model.replacement = "X"

        fixture.model.moveToNext()
        fixture.model.moveToPrevious()
        fixture.model.replaceOne()
        fixture.model.replaceAll()

        #expect(fixture.editor.replaceCalls.isEmpty)
        #expect(fixture.editor.revealed.isEmpty)
        #expect(fixture.editor.findText == "foo bar foo")
        #expect(fixture.editor.findSelection == NSRange(location: 5, length: 0))
    }

    @Test("AC-28: 正規表現が正しくなければ、次・前・置換を押しても文章も選択も変わらない")
    func invalidPatternDoesNothing() {
        let fixture = FindModelFixture("foo b|ar (foo")
        fixture.open("(foo", regex: true)
        fixture.model.replacement = "X"
        #expect(fixture.model.isPatternInvalid)

        fixture.model.moveToNext()
        fixture.model.moveToPrevious()
        fixture.model.replaceOne()
        fixture.model.replaceAll()

        #expect(fixture.editor.replaceCalls.isEmpty)
        #expect(fixture.editor.revealed.isEmpty)
        #expect(fixture.editor.findText == "foo bar (foo")
        #expect(fixture.editor.findSelection == NSRange(location: 5, length: 0))
    }

    @Test("AC-28: 一致が無いときは、次・前を押しても選択は変わらない")
    func noMatchDoesNotMoveSelection() {
        let fixture = FindModelFixture("foo b|ar")
        fixture.open("zzz")
        fixture.model.moveToNext()
        fixture.model.moveToPrevious()
        #expect(fixture.editor.revealed.isEmpty)
        #expect(fixture.editor.findSelection == NSRange(location: 5, length: 0))
    }
}
