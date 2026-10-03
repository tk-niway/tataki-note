import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PromptTextViewKeyEquivalentTests {
    private struct Fixture {
        var window: NSWindow
        var textView: PromptTextView
        var pasteboard: NSPasteboard

        var hasFullLineMark: Bool {
            pasteboard.types?.contains(LineEditing.fullLinePasteboardType) == true
        }
    }

    private final class Received {
        var inputs: [PanelKeyInput] = []
    }

    private func withFixture(
        _ marked: String,
        isFirstResponder: Bool = true,
        consumes: @escaping (PanelKeyInput) -> Bool = { _ in false },
        _ body: (Fixture, Received) throws -> Void
    ) rethrows {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let received = Received()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.pasteboard = pasteboard
        textView.onKeyInput = { input in
            received.inputs.append(input)
            return consumes(input)
        }
        window.contentView = textView
        if isFirstResponder {
            window.makeFirstResponder(textView)
        }
        let (text, selection) = MarkedText.parse(marked)
        textView.string = text
        textView.setSelectedRange(selection)
        try body(Fixture(window: window, textView: textView, pasteboard: pasteboard), received)
    }

    private func keyEvent(
        _ character: String,
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = [.command],
        in window: NSWindow
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func writeFullLine(_ line: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, LineEditing.fullLinePasteboardType], owner: nil)
        pasteboard.setString(line, forType: .string)
        pasteboard.setString("1", forType: LineEditing.fullLinePasteboardType)
    }

    @Test("AC-5: 選択が無い ⌘C は行ごと印つきでクリップボードに入り、⌘X は行ごと切り取る")
    func copyAndCutWorkOnWholeLines() throws {
        try withFixture("alpha\nbe|ta\ngamma") { fixture, _ in
            let handledCopy = fixture.textView.performKeyEquivalent(with: try keyEvent("c", in: fixture.window))
            #expect(handledCopy)
            #expect(fixture.pasteboard.string(forType: .string) == "beta\n")
            #expect(fixture.hasFullLineMark)
            #expect(fixture.textView.string == "alpha\nbeta\ngamma")

            fixture.pasteboard.clearContents()
            let handledCut = fixture.textView.performKeyEquivalent(with: try keyEvent("x", in: fixture.window))
            #expect(handledCut)
            #expect(fixture.textView.string == "alpha\ngamma")
            #expect(fixture.pasteboard.string(forType: .string) == "beta\n")
            #expect(fixture.hasFullLineMark)
        }
    }

    @Test("AC-5: 印つきのクリップボードの ⌘V は、カーソルのある行の上に1行として入る")
    func pasteInsertsFullLineAboveCursorLine() throws {
        try withFixture("a\nb|c") { fixture, _ in
            writeFullLine("x\n", to: fixture.pasteboard)

            let handled = fixture.textView.performKeyEquivalent(with: try keyEvent("v", in: fixture.window))

            #expect(handled)
            #expect(fixture.textView.string == "a\nx\nbc")
        }
    }

    @Test("AC-5: ⌘D はカーソルのある単語を選び、⌘L は行を選ぶ")
    func selectWordAndLine() throws {
        try withFixture("one\ntw|o three") { fixture, _ in
            let handledWord = fixture.textView.performKeyEquivalent(with: try keyEvent("d", in: fixture.window))
            #expect(handledWord)
            #expect(fixture.textView.selectedRange() == NSRange(location: 4, length: 3))

            fixture.textView.setSelectedRange(NSRange(location: 5, length: 0))
            let handledLine = fixture.textView.performKeyEquivalent(with: try keyEvent("l", in: fixture.window))
            #expect(handledLine)
            #expect(fixture.textView.selectedRange() == NSRange(location: 4, length: 9))
            #expect(fixture.textView.string == "one\ntwo three")
        }
    }

    @Test("AC-5: onKeyInput が true を返すキー(確定キーの例 ⌘K)は、⌘ のキーの処理より先に onKeyInput に渡り、文章が変わらない")
    func keyInputIsOfferedBeforeCommandKeys() throws {
        try withFixture("hello|", consumes: { $0.characters == "k" || $0.characters == "c" }) { fixture, received in
            let handledCommit = fixture.textView.performKeyEquivalent(
                with: try keyEvent("k", keyCode: 40, in: fixture.window)
            )
            #expect(handledCommit)
            #expect(received.inputs.map(\.characters) == ["k"])
            #expect(received.inputs.first?.modifiers.contains(.command) == true)
            #expect(fixture.textView.string == "hello")

            fixture.pasteboard.clearContents()
            let handledCopy = fixture.textView.performKeyEquivalent(with: try keyEvent("c", keyCode: 8, in: fixture.window))
            #expect(handledCopy)
            #expect(received.inputs.map(\.characters) == ["k", "c"])
            #expect(fixture.pasteboard.string(forType: .string) == nil)
            #expect(fixture.textView.string == "hello")
        }
    }

    @Test("AC-5: 修飾キーのない ↩ は ⌘ のキーとして処理されず、文章を変えない")
    func plainReturnDoesNotChangeText() throws {
        try withFixture("hel|lo") { fixture, received in
            let event = try keyEvent("\r", keyCode: KeyCode.returnKey, modifiers: [], in: fixture.window)

            _ = fixture.textView.performKeyEquivalent(with: event)

            #expect(received.inputs.map(\.keyCode) == [KeyCode.returnKey])
            #expect(fixture.textView.string == "hello")
            #expect(fixture.textView.selectedRange() == NSRange(location: 3, length: 0))
        }
    }

    @Test("AC-5: ⌘↩ は改行を入れる")
    func commandReturnInsertsNewline() throws {
        try withFixture("ab|") { fixture, _ in
            let event = try keyEvent("\r", keyCode: KeyCode.returnKey, modifiers: [.command], in: fixture.window)

            let handled = fixture.textView.performKeyEquivalent(with: event)

            #expect(handled)
            #expect(fixture.textView.string == "ab\n")
        }
    }

    @Test("AC-5: ファーストレスポンダでないときは、⌘ のキーを処理せず文章も変わらない")
    func ignoresKeysWithoutFocus() throws {
        try withFixture("alpha\nbe|ta", isFirstResponder: false) { fixture, received in
            let handled = fixture.textView.performKeyEquivalent(with: try keyEvent("c", in: fixture.window))

            #expect(!handled)
            #expect(received.inputs.isEmpty)
            #expect(fixture.pasteboard.string(forType: .string) == nil)
            #expect(fixture.textView.string == "alpha\nbeta")
        }
    }
}
