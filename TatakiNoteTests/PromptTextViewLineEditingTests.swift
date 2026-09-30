import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

/// @note p0-1038
@MainActor
final class LineEditingTextViewDelegate: NSObject, NSTextViewDelegate {
    let textUndoManager = UndoManager()
    private(set) var textDidChangeCount = 0

    override init() {
        // @note p0-1039
        textUndoManager.groupsByEvent = false
        super.init()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndoManager
    }

    func textDidChange(_ notification: Notification) {
        textDidChangeCount += 1
    }
}

/// @note p0-1040
@MainActor
final class LineEditingTextViewFixture {
    let textView = PromptTextView()
    let delegate = LineEditingTextViewDelegate()
    let pasteboard = PasteboardFixture.makePasteboard()

    init(_ marked: String) {
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = delegate
        textView.pasteboard = pasteboard
        let (text, selection) = MarkedText.parse(marked)
        textView.string = text
        textView.setSelectedRange(selection)
    }

    /// @note p0-1041
    var marked: String {
        MarkedText.render(textView.string, selection: textView.selectedRange())
    }

    var undoManager: UndoManager {
        delegate.textUndoManager
    }

    /// @note p0-1042
    func writeFullLine(_ line: String) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, LineEditing.fullLinePasteboardType], owner: nil)
        pasteboard.setString(line, forType: .string)
        pasteboard.setString("1", forType: LineEditing.fullLinePasteboardType)
    }

    var hasFullLineMark: Bool {
        pasteboard.types?.contains(LineEditing.fullLinePasteboardType) == true
    }
}

@MainActor
struct PromptTextViewLineEditingTests {
    @Test("AC-1, AC-4: moveLines・duplicateLines で文章と選択が変わる")
    func movesAndDuplicatesLines() {
        let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
        defer { fixture.pasteboard.releaseGlobally() }

        fixture.textView.moveLines(.up)
        #expect(fixture.marked == "tw|o\none\nthree")

        fixture.textView.duplicateLines(.down)
        #expect(fixture.marked == "two\ntw|o\none\nthree")
    }

    @Test("AC-1, AC-4: 4つの行の操作(⌥↑ / ⌥↓ / ⇧⌥↑ / ⇧⌥↓)が、それぞれの移動・複製に振り分けられる")
    func dispatchesArrowCommands() {
        let cases: [(LineArrowCommand, String)] = [
            (.moveLines(.up), "tw|o\none\nthree"),
            (.moveLines(.down), "one\nthree\ntw|o"),
            (.duplicateLines(.up), "one\ntw|o\ntwo\nthree"),
            (.duplicateLines(.down), "one\ntwo\ntw|o\nthree"),
        ]
        for (command, expected) in cases {
            let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
            defer { fixture.pasteboard.releaseGlobally() }

            fixture.textView.performLineArrowCommand(command)
            #expect(fixture.marked == expected, "\(command)")
        }
    }

    @Test("AC-3, AC-17: 改行まで選んだ行を最後の行の下へ移すと、選択は移した行の中身になり、文章の外に出ない")
    func movingLineSelectionBelowLastLineKeepsSelectionInside() {
        let selected = LineEditingTextViewFixture("[a\n]b")
        defer { selected.pasteboard.releaseGlobally() }
        selected.textView.moveLines(.down)
        #expect(selected.textView.string == "b\na")
        #expect(selected.textView.selectedRange() == NSRange(location: 2, length: 1))

        // @note p0-1043
        let expanded = LineEditingTextViewFixture("|a\nb")
        defer { expanded.pasteboard.releaseGlobally() }
        expanded.textView.expandLineSelection()
        #expect(expanded.marked == "[a\n]b")
        expanded.textView.moveLines(.down)
        #expect(expanded.textView.string == "b\na")
        #expect(expanded.textView.selectedRange() == NSRange(location: 2, length: 1))
    }

    @Test("AC-5: 選択なしのコピーで、カーソルのある行が改行ごと印つきでクリップボードに入り、文章とカーソルは変わらない")
    func copiesCursorLine() {
        let middle = LineEditingTextViewFixture("alpha\nbe|ta\ngamma")
        defer { middle.pasteboard.releaseGlobally() }
        middle.textView.copyLineOrSelection()
        #expect(middle.pasteboard.string(forType: .string) == "beta\n")
        #expect(middle.hasFullLineMark)
        #expect(middle.marked == "alpha\nbe|ta\ngamma")

        let last = LineEditingTextViewFixture("alpha\nbeta\ngam|ma")
        defer { last.pasteboard.releaseGlobally() }
        last.textView.copyLineOrSelection()
        #expect(last.pasteboard.string(forType: .string) == "gamma\n")
        #expect(last.hasFullLineMark)
        #expect(last.marked == "alpha\nbeta\ngam|ma")
    }

    @Test("AC-6: 選択なしの切り取りで、カーソルのある行が改行ごと消えて印つきでクリップボードに入る")
    func cutsCursorLine() {
        let middle = LineEditingTextViewFixture("alpha\nbe|ta\ngamma")
        defer { middle.pasteboard.releaseGlobally() }
        middle.textView.cutLineOrSelection()
        #expect(middle.marked == "alpha\n|gamma")
        #expect(middle.pasteboard.string(forType: .string) == "beta\n")
        #expect(middle.hasFullLineMark)

        // @note p0-1044
        let last = LineEditingTextViewFixture("alpha\nga|mma")
        defer { last.pasteboard.releaseGlobally() }
        last.textView.cutLineOrSelection()
        #expect(last.marked == "alpha|")
        #expect(last.pasteboard.string(forType: .string) == "gamma\n")
        #expect(last.hasFullLineMark)
    }

    @Test("AC-7: 印つきのクリップボードで選択なしの貼り付けをすると、カーソルのある行の上に1行として入る")
    func pastesFullLineAboveCursorLine() {
        let fixture = LineEditingTextViewFixture("a\nb|c")
        defer { fixture.pasteboard.releaseGlobally() }
        fixture.writeFullLine("x\n")

        fixture.textView.pasteLineOrClipboard()
        #expect(fixture.marked == "a\nx\nb|c")
    }

    @Test("AC-10: expandLineSelection を続けて呼ぶと、1行ずつ選択が広がり、最後の行まで選んだら変わらない")
    func expandsLineSelectionRepeatedly() {
        let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
        defer { fixture.pasteboard.releaseGlobally() }

        fixture.textView.expandLineSelection()
        #expect(fixture.marked == "one\n[two\n]three")
        fixture.textView.expandLineSelection()
        #expect(fixture.marked == "one\n[two\nthree]")
        fixture.textView.expandLineSelection()
        #expect(fixture.marked == "one\n[two\nthree]")
    }

    @Test("AC-11: selectWordAtCursor はカーソルのある単語を選び、もう一度呼んでも選択は変わらない")
    func selectsWordAtCursor() {
        let english = LineEditingTextViewFixture("he|llo world")
        defer { english.pasteboard.releaseGlobally() }
        english.textView.selectWordAtCursor()
        #expect(english.marked == "[hello] world")
        english.textView.selectWordAtCursor()
        #expect(english.marked == "[hello] world")

        // @note p0-1045
        let japanese = LineEditingTextViewFixture("日|本語の文章")
        defer { japanese.pasteboard.releaseGlobally() }
        japanese.textView.selectWordAtCursor()
        let word = japanese.textView.selectedRange()
        #expect(word.length > 0)
        #expect(word.location <= 1 && 1 <= NSMaxRange(word))
        #expect(word.length < ("日本語の文章" as NSString).length)
        japanese.textView.selectWordAtCursor()
        #expect(japanese.textView.selectedRange() == word)
    }

    @Test("AC-14: 移動・複製・行ごと切り取り・行ごと貼り付けは、undo で1回ずつ操作の前に戻り、redo でやり直せる")
    func undoesAndRedoesEachOperation() {
        let operations: [(String, (LineEditingTextViewFixture) -> Void)] = [
            ("移動", { $0.textView.moveLines(.up) }),
            ("複製", { $0.textView.duplicateLines(.down) }),
            ("行ごと切り取り", { $0.textView.cutLineOrSelection() }),
            ("行ごと貼り付け", { fixture in
                fixture.writeFullLine("x\n")
                fixture.textView.pasteLineOrClipboard()
            }),
        ]
        for (label, operation) in operations {
            let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
            defer { fixture.pasteboard.releaseGlobally() }
            let before = fixture.textView.string

            operation(fixture)
            let after = fixture.textView.string
            #expect(after != before, "\(label)")

            fixture.undoManager.undo()
            #expect(fixture.textView.string == before, "\(label)")
            fixture.undoManager.redo()
            #expect(fixture.textView.string == after, "\(label)")
        }
    }

    @Test("AC-14: 2回続けて移動してから undo を1回すると、1回分だけ戻る")
    func undoRevertsOneMoveAtATime() {
        let fixture = LineEditingTextViewFixture("one\ntwo\nthre|e")
        defer { fixture.pasteboard.releaseGlobally() }

        fixture.textView.moveLines(.up)
        fixture.textView.moveLines(.up)
        #expect(fixture.textView.string == "three\none\ntwo")

        fixture.undoManager.undo()
        #expect(fixture.textView.string == "one\nthree\ntwo")
        fixture.undoManager.undo()
        #expect(fixture.textView.string == "one\ntwo\nthree")
    }

    @Test("AC-15: 行の操作のたびに textDidChange が呼ばれる(下書きに書き戻す経路)")
    func notifiesTextDidChange() {
        let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
        defer { fixture.pasteboard.releaseGlobally() }
        var count = fixture.delegate.textDidChangeCount

        fixture.textView.moveLines(.down)
        #expect(fixture.delegate.textDidChangeCount == count + 1)
        count = fixture.delegate.textDidChangeCount

        fixture.textView.duplicateLines(.up)
        #expect(fixture.delegate.textDidChangeCount == count + 1)
        count = fixture.delegate.textDidChangeCount

        fixture.textView.cutLineOrSelection()
        #expect(fixture.delegate.textDidChangeCount == count + 1)
        count = fixture.delegate.textDidChangeCount

        fixture.textView.pasteLineOrClipboard()
        #expect(fixture.delegate.textDidChangeCount == count + 1)
    }

    @Test("AC-15: 行の操作で変わった文章が、PromptTextEditor の Coordinator を通して下書きに書き戻される")
    func writesBackToDraftThroughCoordinator() {
        let fixture = LineEditingTextViewFixture("one\ntw|o\nthree")
        defer { fixture.pasteboard.releaseGlobally() }
        let draft = DraftBox()
        let coordinator = PromptTextEditor.Coordinator(
            text: Binding(get: { draft.text }, set: { draft.text = $0 })
        )
        fixture.textView.delegate = coordinator

        fixture.textView.moveLines(.up)
        #expect(draft.text == "two\none\nthree")

        fixture.textView.cutLineOrSelection()
        #expect(draft.text == "one\nthree")
        withExtendedLifetime(coordinator) {}
    }
}

/// @note p0-1046
private final class DraftBox {
    var text = ""
}
