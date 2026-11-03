import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class FindTextViewDelegate: NSObject, NSTextViewDelegate {
    let textUndoManager = UndoManager()

    override init() {
        textUndoManager.groupsByEvent = false
        super.init()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndoManager
    }
}

@MainActor
private final class FindTextViewFixture {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
        styleMask: [.titled],
        backing: .buffered,
        defer: true
    )
    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
    let delegate = FindTextViewDelegate()
    let model = FindModel()
    private(set) var stringChangeCount = 0
    private(set) var selectionChangeCount = 0

    init(_ marked: String) {
        window.isReleasedWhenClosed = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = delegate
        let (text, selection) = MarkedText.parse(marked)
        textView.string = text
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
        model.editor = { [weak textView] in textView }
        textView.onStringChange = { [weak self] in
            self?.stringChangeCount += 1
            self?.model.textDidChange()
        }
        textView.onSelectionChange = { [weak self] in
            self?.selectionChangeCount += 1
            self?.model.selectionDidChange()
        }
    }

    var undoManager: UndoManager {
        delegate.textUndoManager
    }

    isolated deinit {
        textView.inputContext?.discardMarkedText()
        window.makeFirstResponder(nil)
        window.close()
    }
}

@MainActor
struct PromptTextViewFindTests {
    @Test("AC-24: showFindHighlights は範囲を文章に収めて記録し、閉じると空になる。文章の属性は変えない")
    func recordsHighlightsWithoutTouchingTextStorage() throws {
        let fixture = FindTextViewFixture("foo bar foo")
        let storage = try #require(fixture.textView.textStorage)
        let before = NSAttributedString(attributedString: storage)

        fixture.textView.showFindHighlights(
            [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3), NSRange(location: 9, length: 9)],
            current: NSRange(location: 8, length: 3)
        )
        #expect(fixture.textView.findHighlights == [
            FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: false),
            FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true),
        ])
        #expect(NSAttributedString(attributedString: storage).isEqual(to: before))
        #expect(fixture.undoManager.canUndo == false)

        fixture.textView.showFindHighlights([], current: nil)
        #expect(fixture.textView.findHighlights.isEmpty)
        #expect(NSAttributedString(attributedString: storage).isEqual(to: before))
    }

    @Test("AC-24: 検索バーを開くと入力欄の一致がハイライトされ、閉じると消える")
    func modelDrivesHighlights() {
        let fixture = FindTextViewFixture("|foo bar foo")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "foo")
        #expect(fixture.textView.findHighlights.count == 2)
        #expect(fixture.textView.findHighlights.filter(\.isCurrent).map(\.range) == [NSRange(location: 0, length: 3)])

        fixture.model.close()
        #expect(fixture.textView.findHighlights.isEmpty)
    }

    @Test("AC-23: revealFindMatch は一致を選び、文章の外に出る範囲は収める")
    func revealSelectsMatch() {
        let fixture = FindTextViewFixture("foo bar foo|")
        fixture.textView.revealFindMatch(NSRange(location: 8, length: 3))
        #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 3))

        fixture.textView.revealFindMatch(NSRange(location: 9, length: 20))
        #expect(fixture.textView.selectedRange() == NSRange(location: 9, length: 2))
    }

    @Test("AC-25: 文章の入れ替え・編集・選択の変化が通知され、検索語はそのままで選択を動かさずに数え直す")
    func notifiesAndResearches() {
        let fixture = FindTextViewFixture("foo| bar")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "foo")
        fixture.textView.setSelectedRange(NSRange(location: 3, length: 0))
        let selectionCount = fixture.selectionChangeCount
        let stringCount = fixture.stringChangeCount

        fixture.textView.string = "foo bar foo foo"
        #expect(fixture.stringChangeCount == stringCount + 1)
        #expect(fixture.model.query == "foo")
        #expect(fixture.model.matches.count == 3)

        fixture.textView.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(fixture.selectionChangeCount > selectionCount)
        #expect(fixture.textView.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test("AC-25: 利用者の編集(didChangeText)も文章の変化として通知される")
    func userEditNotifies() {
        let fixture = FindTextViewFixture("foo| bar")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "bar")
        let count = fixture.stringChangeCount

        fixture.undoManager.beginUndoGrouping()
        fixture.textView.insertText(" bar", replacementRange: NSRange(location: 3, length: 0))
        fixture.undoManager.endUndoGrouping()
        #expect(fixture.stringChangeCount > count)
        #expect(fixture.model.matches.count == 2)
    }

    @Test("AC-26: replaceForFind は1か所を置き換えて直後を選び、⌘Z の1回で戻り、戻すと文章の変化として知らせる")
    func replaceOneIsUndoable() {
        let fixture = FindTextViewFixture("|foo bar foo")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "foo")
        fixture.model.replacement = "X"

        fixture.model.replaceOne()
        #expect(fixture.textView.string == "X bar foo")
        #expect(fixture.model.matches == [NSRange(location: 6, length: 3)])
        #expect(fixture.textView.selectedRange() == NSRange(location: 6, length: 3))

        fixture.model.replaceOne()
        #expect(fixture.textView.string == "X bar X")

        let beforeUndo = fixture.stringChangeCount
        fixture.undoManager.undo()
        #expect(fixture.textView.string == "X bar foo")
        #expect(fixture.stringChangeCount > beforeUndo)
        #expect(fixture.model.matches == [NSRange(location: 6, length: 3)])

        fixture.undoManager.undo()
        #expect(fixture.textView.string == "foo bar foo")
        #expect(fixture.model.matches.count == 2)
    }

    @Test("AC-26: 選択が一致でないとき、次を置換は文章を変えず次の一致へ移るだけ")
    func replaceOneOnNonMatchOnlyMoves() {
        let fixture = FindTextViewFixture("foo b|ar foo")
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "foo")
        fixture.textView.setSelectedRange(NSRange(location: 5, length: 0))
        fixture.model.replacement = "X"

        fixture.model.replaceOne()
        #expect(fixture.textView.string == "foo bar foo")
        #expect(fixture.textView.selectedRange() == NSRange(location: 8, length: 3))
        #expect(fixture.undoManager.canUndo == false)
    }

    @Test("AC-27: すべて置換は 19,999 件を超えても全部を置き換え、⌘Z の1回で元に戻り、戻した文章で数え直す")
    func replaceAllIsOneUndo() {
        let original = String(repeating: "a ", count: 20_000)
        let fixture = FindTextViewFixture("|" + original)
        fixture.model.open(revealsReplace: false, movesFocus: false, seed: "a")
        #expect(fixture.model.isTruncated)
        fixture.model.replacement = "bb"

        fixture.model.replaceAll()
        #expect(fixture.textView.string == String(repeating: "bb ", count: 20_000))
        #expect(fixture.textView.selectedRange() == NSRange(location: 59_999, length: 0))
        #expect(fixture.model.matches.isEmpty)

        fixture.undoManager.undo()
        #expect(fixture.textView.string == original)
        #expect(fixture.model.matches.count == TextSearch.matchLimit)
        #expect(fixture.model.isTruncated)
        #expect(fixture.undoManager.canUndo == false)
    }

    @Test("AC-27: 範囲が重ならない複数の置き換えを位置の順に依らず1回で入れ、undo で戻る")
    func replaceForFindAppliesUnorderedEditsAtOnce() {
        let fixture = FindTextViewFixture("one two three")
        fixture.textView.replaceForFind(
            [
                FindEdit(range: NSRange(location: 8, length: 5), replacement: "3"),
                FindEdit(range: NSRange(location: 0, length: 3), replacement: "1"),
            ],
            selectionAfter: NSRange(location: 3, length: 0)
        )
        #expect(fixture.textView.string == "1 two 3")
        #expect(fixture.textView.selectedRange() == NSRange(location: 3, length: 0))

        fixture.undoManager.undo()
        #expect(fixture.textView.string == "one two three")
    }

    @Test("AC-28: 検索語が空のとき、次・前・置換を押しても入力欄の文章も選択も変わらない")
    func emptyQueryLeavesTextViewUntouched() {
        let fixture = FindTextViewFixture("foo b|ar foo")
        fixture.model.open(revealsReplace: true, movesFocus: false, seed: nil)
        fixture.model.replacement = "X"
        let stringCount = fixture.stringChangeCount

        fixture.model.moveToNext()
        fixture.model.moveToPrevious()
        fixture.model.replaceOne()
        fixture.model.replaceAll()

        #expect(fixture.textView.string == "foo bar foo")
        #expect(fixture.textView.selectedRange() == NSRange(location: 5, length: 0))
        #expect(fixture.stringChangeCount == stringCount)
        #expect(fixture.undoManager.canUndo == false)
    }
}
