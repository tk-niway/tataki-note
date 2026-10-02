import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct PracticeTextEditorTests {
    private final class TextBox {
        var value = ""
    }

    private struct Fixture {
        var window: NSWindow
        var textView: PracticeTextView
        var pasteboard: NSPasteboard
        var box: TextBox
        var coordinator: PracticeTextEditor.Coordinator
    }

    private func withFixture(
        isFirstResponder: Bool = true,
        _ body: (Fixture) throws -> Void
    ) rethrows {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let box = TextBox()
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let coordinator = PracticeTextEditor.Coordinator(text: binding)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = PracticeTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        textView.delegate = coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.pasteboard = pasteboard
        window.contentView = textView
        if isFirstResponder {
            window.makeFirstResponder(textView)
        }
        try body(Fixture(window: window, textView: textView, pasteboard: pasteboard, box: box, coordinator: coordinator))
    }

    private func commandKeyEvent(_ character: String, shift: Bool = false, in window: NSWindow) throws -> NSEvent {
        let modifiers: NSEvent.ModifierFlags = shift ? [.command, .shift] : [.command]
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 9
        ))
    }

    @Test("AC-24: フォーカスがあると ⌘V でクリップボードの文字列が入り、練習の文章も変わる")
    func pasteInsertsClipboardStringWhenFocused() throws {
        try withFixture { fixture in
            fixture.pasteboard.clearContents()
            fixture.pasteboard.setString("abc\ndef", forType: .string)

            let paste = try commandKeyEvent("v", in: fixture.window)
            let handled = fixture.textView.performKeyEquivalent(with: paste)

            #expect(handled)
            #expect(fixture.textView.string == "abc\ndef")
            #expect(fixture.box.value == "abc\ndef")
        }
    }

    @Test("AC-24: ⌘V は選択範囲を置き換え、カーソルの位置に入る")
    func pasteReplacesSelection() throws {
        try withFixture { fixture in
            fixture.textView.string = "Hello World"
            fixture.textView.setSelectedRange(NSRange(location: 6, length: 5))
            fixture.pasteboard.clearContents()
            fixture.pasteboard.setString("Tataki", forType: .string)

            let paste = try commandKeyEvent("v", in: fixture.window)
            let handled = fixture.textView.performKeyEquivalent(with: paste)

            #expect(handled)
            #expect(fixture.textView.string == "Hello Tataki")
            #expect(fixture.box.value == "Hello Tataki")
        }
    }

    @Test("AC-24: フォーカスを持っていないと ⌘V では何も入らない")
    func pasteDoesNothingWithoutFocus() throws {
        try withFixture(isFirstResponder: false) { fixture in
            fixture.pasteboard.clearContents()
            fixture.pasteboard.setString("abc", forType: .string)

            let paste = try commandKeyEvent("v", in: fixture.window)
            let handled = fixture.textView.performKeyEquivalent(with: paste)

            #expect(!handled)
            #expect(fixture.textView.string.isEmpty)
            #expect(fixture.box.value.isEmpty)
        }
    }

    @Test("AC-24: クリップボードに文字列が無いと ⌘V は何も入れない")
    func pasteWithoutStringInsertsNothing() throws {
        try withFixture { fixture in
            fixture.textView.string = "keep"
            fixture.pasteboard.clearContents()

            let paste = try commandKeyEvent("v", in: fixture.window)
            let handled = fixture.textView.performKeyEquivalent(with: paste)

            #expect(handled)
            #expect(fixture.textView.string == "keep")
        }
    }

    @Test("AC-24: ⌘A は全選択、⌘C は選択をクリップボードへ、⌘X は切り取る")
    func selectAllCopyAndCut() throws {
        let generalChangeCount = NSPasteboard.general.changeCount
        try withFixture { fixture in
            fixture.textView.string = "copy me"
            let selectAll = try commandKeyEvent("a", in: fixture.window)
            let copy = try commandKeyEvent("c", in: fixture.window)
            let cut = try commandKeyEvent("x", in: fixture.window)

            #expect(fixture.textView.performKeyEquivalent(with: selectAll))
            #expect(fixture.textView.selectedRange() == NSRange(location: 0, length: 7))

            #expect(fixture.textView.performKeyEquivalent(with: copy))
            #expect(fixture.textView.string == "copy me")
            #expect(fixture.pasteboard.string(forType: .string) == "copy me")

            fixture.pasteboard.clearContents()
            #expect(fixture.textView.performKeyEquivalent(with: cut))
            #expect(fixture.pasteboard.string(forType: .string) == "copy me")
            #expect(fixture.textView.string.isEmpty)
            #expect(fixture.box.value.isEmpty)
        }
        #expect(NSPasteboard.general.changeCount == generalChangeCount)
    }

    @Test("AC-24: ⌘ 以外の組み合わせや対象外のキーは処理しない")
    func ignoresOtherKeys() throws {
        try withFixture { fixture in
            fixture.pasteboard.clearContents()
            fixture.pasteboard.setString("abc", forType: .string)
            let shiftedPaste = try commandKeyEvent("v", shift: true, in: fixture.window)

            #expect(!fixture.textView.performKeyEquivalent(with: shiftedPaste))
            #expect(fixture.textView.string.isEmpty)
        }
    }
}
