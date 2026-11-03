import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class WindowUndoProbe: NSObject {
    var undoCount = 0

    @objc func undo(_ object: Any?) {
        undoCount += 1
    }
}

@MainActor
struct FindBarNSTextFieldTests {
    @MainActor
    private struct Fixture {
        let window: NSWindow
        let field: FindBarNSTextField
        let probe: WindowUndoProbe

        var editor: NSTextView? { field.currentEditor() as? NSTextView }
    }

    private func withFixture(startsEditing: Bool = true, _ body: (Fixture) throws -> Void) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let field = FindBarNSTextField(findField: .find)
        field.frame = NSRect(x: 10, y: 10, width: 200, height: 24)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        container.addSubview(field)
        window.contentView = container
        if startsEditing {
            #expect(window.makeFirstResponder(field))
        }
        let probe = WindowUndoProbe()
        let windowUndo = try #require(window.undoManager)
        windowUndo.registerUndo(withTarget: probe, selector: #selector(WindowUndoProbe.undo(_:)), object: nil)
        settleRunLoop()
        try body(Fixture(window: window, field: field, probe: probe))
        window.contentView = nil
    }

    private func settleRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func type(_ text: String, into fixture: Fixture) throws {
        let editor = try #require(fixture.editor)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settleRunLoop()
    }

    private func keyEvent(
        _ character: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
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

    @Test("AC-43: 編集中の欄の取り消しの履歴は欄専用のもので、窓の履歴とは別")
    func fieldEditorUsesFieldOwnUndoManager() throws {
        try withFixture { fixture in
            let editor = try #require(fixture.editor)
            let fieldUndo = try #require(editor.undoManager)
            let windowUndo = try #require(fixture.window.undoManager)

            #expect(fieldUndo === fixture.field.fieldUndoManager)
            #expect(fieldUndo !== windowUndo)
        }
    }

    @Test("AC-43: 欄で打ってから ⌘Z を押すと欄の文字だけが戻り、窓の取り消しは残る")
    func commandZUndoesOnlyFieldText() throws {
        try withFixture { fixture in
            try type("abc", into: fixture)
            #expect(fixture.field.currentEditor()?.string == "abc")
            let windowUndo = try #require(fixture.window.undoManager)

            let handled = fixture.field.performKeyEquivalent(
                with: try keyEvent("z", keyCode: 6, modifiers: [.command], in: fixture.window)
            )

            #expect(handled)
            #expect(fixture.field.currentEditor()?.string == "")
            #expect(fixture.probe.undoCount == 0)
            #expect(windowUndo.canUndo)
        }
    }

    @Test("AC-43: ⇧⌘Z で、戻した欄の文字をやり直せる")
    func shiftCommandZRedoesFieldText() throws {
        try withFixture { fixture in
            try type("abc", into: fixture)
            #expect(fixture.field.performKeyEquivalent(
                with: try keyEvent("z", keyCode: 6, modifiers: [.command], in: fixture.window)
            ))
            #expect(fixture.field.currentEditor()?.string == "")

            let handled = fixture.field.performKeyEquivalent(
                with: try keyEvent("z", keyCode: 6, modifiers: [.command, .shift], in: fixture.window)
            )

            #expect(handled)
            #expect(fixture.field.currentEditor()?.string == "abc")
        }
    }

    @Test("AC-43: ⌘A で欄の文字が全部選ばれる")
    func commandASelectsAllFieldText() throws {
        try withFixture { fixture in
            try type("abc def", into: fixture)
            let editor = try #require(fixture.editor)
            editor.setSelectedRange(NSRange(location: 2, length: 0))

            let handled = fixture.field.performKeyEquivalent(
                with: try keyEvent("a", keyCode: 0, modifiers: [.command], in: fixture.window)
            )

            #expect(handled)
            #expect(editor.selectedRange() == NSRange(location: 0, length: 7))
        }
    }

    @Test("AC-43: 欄を編集していないときは、⌘A・⌘Z を欄の編集として受けない")
    func keysAreIgnoredWhenNotEditing() throws {
        try withFixture(startsEditing: false) { fixture in
            #expect(fixture.field.currentEditor() == nil)
            fixture.field.stringValue = "abc"

            let selectAll = fixture.field.performKeyEquivalent(
                with: try keyEvent("a", keyCode: 0, modifiers: [.command], in: fixture.window)
            )
            let undo = fixture.field.performKeyEquivalent(
                with: try keyEvent("z", keyCode: 6, modifiers: [.command], in: fixture.window)
            )

            #expect(!selectAll)
            #expect(!undo)
            #expect(fixture.field.stringValue == "abc")
            #expect(fixture.probe.undoCount == 0)
        }
    }

    @Test("AC-43: 編集の操作に当たらない ⌘ のキーは受けず、文字も変わらない")
    func otherCommandKeysAreNotHandled() throws {
        try withFixture { fixture in
            try type("abc", into: fixture)

            for (character, keyCode) in [("f", UInt16(3)), ("g", UInt16(5)), ("s", UInt16(1))] {
                let handled = fixture.field.performKeyEquivalent(
                    with: try keyEvent(character, keyCode: keyCode, modifiers: [.command], in: fixture.window)
                )
                #expect(!handled, "⌘\(character)")
            }
            #expect(fixture.field.currentEditor()?.string == "abc")
        }
    }

    @Test("AC-43: 欄の文字の改行は「↵」で見せ、モデルへは改行に戻す")
    func newlinesAreShownAsMarks() {
        #expect(FindBarTextField.displayText("a\nb\r\nc\rd") == "a↵b↵c↵d")
        #expect(FindBarTextField.modelText("a↵b") == "a\nb")
        #expect(FindBarTextField.modelText(FindBarTextField.displayText("秒\n\n指摘")) == "秒\n\n指摘")
    }
}
