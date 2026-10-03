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

    private func returnKeyEvent(
        keyCode: UInt16 = 36,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test("AC-6: ↩ は今の文章で送信を呼んで改行を入れず、⇧↩ は改行を入れて送信を呼ばない")
    func returnSendsAndShiftReturnInsertsNewline() throws {
        try withFixture { fixture in
            var sent: [String] = []
            fixture.textView.onSend = { sent.append($0); return true }
            fixture.textView.string = "hi"
            fixture.textView.setSelectedRange(NSRange(location: 2, length: 0))

            fixture.textView.keyDown(with: try returnKeyEvent(in: fixture.window))
            #expect(sent == ["hi"])
            #expect(fixture.textView.string == "hi")

            fixture.textView.keyDown(with: try returnKeyEvent(modifiers: [.shift], in: fixture.window))
            #expect(sent == ["hi"])
            #expect(fixture.textView.string == "hi\n")
        }
    }

    @Test("AC-6: ⌘C・⌘X・⌘V は選択だけを扱い、テスト用のクリップボードを使い、一般のクリップボードを変えない")
    func clipboardKeysUseSelectionAndInjectedPasteboard() throws {
        let generalChangeCount = NSPasteboard.general.changeCount
        try withFixture { fixture in
            fixture.textView.string = "one two"
            let copy = try commandKeyEvent("c", in: fixture.window)
            let cut = try commandKeyEvent("x", in: fixture.window)
            let paste = try commandKeyEvent("v", in: fixture.window)
            fixture.textView.setSelectedRange(NSRange(location: 0, length: 3))

            #expect(fixture.textView.performKeyEquivalent(with: copy))
            #expect(fixture.pasteboard.string(forType: .string) == "one")
            #expect(fixture.textView.string == "one two")

            fixture.textView.setSelectedRange(NSRange(location: 4, length: 3))
            #expect(fixture.textView.performKeyEquivalent(with: cut))
            #expect(fixture.pasteboard.string(forType: .string) == "two")
            #expect(fixture.textView.string == "one ")

            fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
            #expect(fixture.textView.performKeyEquivalent(with: paste))
            #expect(fixture.textView.string == "twoone ")
            #expect(fixture.box.value == "twoone ")

            fixture.pasteboard.clearContents()
            fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
            #expect(fixture.textView.performKeyEquivalent(with: copy))
            #expect(fixture.pasteboard.string(forType: .string) == nil)
        }
        #expect(NSPasteboard.general.changeCount == generalChangeCount)
    }

    @Test("AC-10: 練習用の入力欄は、空のときにプレースホルダーを描く対象で、アクセシビリティの値もその文になる。パネルの入力欄は描く対象にならない")
    func placeholderIsDrawnOnlyInPracticeField() {
        withFixture { fixture in
            fixture.textView.placeholder = "メッセージを入力"

            #expect(fixture.textView.drawsPlaceholder)
            #expect(fixture.textView.accessibilityPlaceholderValue() == "メッセージを入力")
        }
        #expect(!PromptTextView().drawsPlaceholder)
    }

    @Test("AC-9: 変換中でない ↩ は、入力欄の今の文字列で送信を呼び、改行を入れない")
    func returnSendsCurrentTextWithoutNewline() throws {
        try withFixture { fixture in
            var sent: [String] = []
            fixture.textView.onSend = { sent.append($0); return true }
            fixture.textView.string = "hello"
            fixture.textView.setSelectedRange(NSRange(location: 5, length: 0))

            fixture.textView.keyDown(with: try returnKeyEvent(in: fixture.window))

            #expect(sent == ["hello"])
            #expect(fixture.textView.string == "hello")
        }
    }

    @Test("AC-9: テンキーの Enter も送信する")
    func keypadEnterSends() throws {
        try withFixture { fixture in
            var sent: [String] = []
            fixture.textView.onSend = { sent.append($0); return true }
            fixture.textView.string = "pad"

            fixture.textView.keyDown(with: try returnKeyEvent(keyCode: 76, in: fixture.window))

            #expect(sent == ["pad"])
            #expect(fixture.textView.string == "pad")
        }
    }

    @Test("AC-9: ⇧↩ は改行を入れ、送信は呼ばない")
    func shiftReturnInsertsNewlineWithoutSending() throws {
        try withFixture { fixture in
            var sent: [String] = []
            fixture.textView.onSend = { sent.append($0); return true }
            fixture.textView.string = "ab"
            fixture.textView.setSelectedRange(NSRange(location: 2, length: 0))

            fixture.textView.keyDown(with: try returnKeyEvent(modifiers: [.shift], in: fixture.window))

            #expect(sent.isEmpty)
            #expect(fixture.textView.string == "ab\n")
            #expect(fixture.box.value == "ab\n")
        }
    }

    @Test("AC-9: ⌘↩ は送信を呼ばない")
    func commandReturnDoesNotSend() throws {
        try withFixture { fixture in
            var sent: [String] = []
            fixture.textView.onSend = { sent.append($0); return true }
            fixture.textView.string = "keep"

            fixture.textView.keyDown(with: try returnKeyEvent(modifiers: [.command], in: fixture.window))

            #expect(sent.isEmpty)
        }
    }

    @Test("入力欄のプレースホルダーを、アクセシビリティの値にも渡す")
    func placeholderIsExposedToAccessibility() {
        withFixture { fixture in
            fixture.textView.placeholder = "メッセージを入力"

            #expect(fixture.textView.accessibilityPlaceholderValue() == "メッセージを入力")
        }
    }

    @Test("AC-27: フォーカスがあると ⌘V でクリップボードの文字列が入り、練習の文章も変わる")
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

    @Test("AC-27: ⌘V は選択範囲を置き換え、カーソルの位置に入る")
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

    @Test("AC-27: フォーカスを持っていないと ⌘V では何も入らない")
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

    @Test("AC-27: クリップボードに文字列が無いと ⌘V は何も入れない")
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

    @Test("AC-27: ⌘A は全選択、⌘C は選択をクリップボードへ、⌘X は切り取る")
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

    @Test("AC-27: ⌘ 以外の組み合わせや対象外のキーは処理しない")
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
