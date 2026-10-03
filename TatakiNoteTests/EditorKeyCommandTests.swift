import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct EditorKeyCommandTests {
    @MainActor
    private struct Fixture {
        var window: NSWindow
        var textView: EditorTextView
        var pasteboard: NSPasteboard

        func press(_ character: String, modifiers: NSEvent.ModifierFlags = [.command]) -> Bool {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: 0
            ) else {
                Issue.record("キーのイベントを作れなかった")
                return false
            }
            return textView.performKeyEquivalent(with: event)
        }
    }

    private enum Kind {
        case panel
        case practice
    }

    private func withFixture(_ kind: Kind, _ marked: String, _ body: (Fixture) -> Void) {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        let textView: EditorTextView = switch kind {
        case .panel: PromptTextView(frame: frame)
        case .practice: PracticeTextView(frame: frame)
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.pasteboard = pasteboard
        window.contentView = textView
        window.makeFirstResponder(textView)
        let (text, selection) = MarkedText.parse(marked)
        textView.string = text
        textView.setSelectedRange(selection)
        body(Fixture(window: window, textView: textView, pasteboard: pasteboard))
    }

    private func candidate(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags,
        _ characters: String
    ) -> PanelShortcutCandidate {
        PanelShortcutCandidate(shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers), characters: characters)
    }

    private func rejection(for candidate: PanelShortcutCandidate) -> PanelShortcutRejection? {
        PanelShortcutRules.rejection(
            for: candidate,
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
    }

    // MARK: - AC-13

    @Test("AC-13: ⌘ のキーの対応表が今と同じで、パネルだけで効く操作が決まっている")
    func commandTable() {
        let table: [(NSEvent.ModifierFlags, String, EditorKeyCommand)] = [
            ([.command], "a", .selectAll),
            ([.command], "c", .copy),
            ([.command], "x", .cut),
            ([.command], "v", .paste),
            ([.command], "z", .undo),
            ([.command, .shift], "z", .redo),
            ([.command], "d", .selectWord),
            ([.command], "l", .selectLine),
        ]
        for (modifiers, character, expected) in table {
            #expect(EditorKeyCommand.command(modifiers: modifiers, character: character) == expected)
        }
        #expect(EditorKeyCommand.command(modifiers: [.command], character: "h") == nil)
        #expect(EditorKeyCommand.command(modifiers: [.command], character: "b") == nil)
        #expect(EditorKeyCommand.command(modifiers: [.command, .shift], character: "c") == nil)
        #expect(EditorKeyCommand.command(modifiers: [.command, .option], character: "v") == nil)
        #expect(EditorKeyCommand.command(modifiers: [], character: "c") == nil)

        let panelOnly = EditorKeyCommand.allCases.filter(\.isPanelOnly)
        #expect(Set(panelOnly) == [.moveLines, .duplicateLines, .selectLine, .selectWord])
        #expect(EditorKeyCommand.moveLines.keyEquivalent == nil)
        #expect(EditorKeyCommand.duplicateLines.keyEquivalent == nil)
    }

    @Test("AC-13: パネルの入力欄は ⌘A・⌘C・⌘X・⌘V・⌘D・⌘L を処理し、⌘H は処理しない")
    func panelHandlesEditingKeys() {
        withFixture(.panel, "alpha\nbe|ta\ngamma") { fixture in
            #expect(fixture.press("a"))
            #expect(fixture.textView.selectedRange() == NSRange(location: 0, length: 16))

            fixture.textView.setSelectedRange(NSRange(location: 8, length: 0))
            #expect(fixture.press("c"))
            #expect(fixture.pasteboard.string(forType: .string) == "beta\n")

            #expect(fixture.press("x"))
            #expect(fixture.textView.string == "alpha\ngamma")

            #expect(fixture.press("v"))
            #expect(fixture.textView.string == "alpha\nbeta\ngamma")
        }
        withFixture(.panel, "one\ntw|o three") { fixture in
            #expect(fixture.press("d"))
            #expect(fixture.textView.selectedRange() == NSRange(location: 4, length: 3))

            fixture.textView.setSelectedRange(NSRange(location: 5, length: 0))
            #expect(fixture.press("l"))
            #expect(fixture.textView.selectedRange() == NSRange(location: 4, length: 9))
        }
        withFixture(.panel, "one|") { fixture in
            #expect(!fixture.press("h"))
            #expect(fixture.textView.string == "one")
            #expect(fixture.textView.selectedRange() == NSRange(location: 3, length: 0))
        }
    }

    @Test("AC-13: 練習用の入力欄は ⌘A・⌘C・⌘X・⌘V を処理し、⌘D・⌘L・⌘H は処理しない")
    func practiceHandlesEditingKeysExceptPanelOnly() {
        withFixture(.practice, "|one two") { fixture in
            #expect(fixture.press("a"))
            #expect(fixture.textView.selectedRange() == NSRange(location: 0, length: 7))

            #expect(fixture.press("c"))
            #expect(fixture.pasteboard.string(forType: .string) == "one two")

            #expect(fixture.press("x"))
            #expect(fixture.textView.string == "")

            #expect(fixture.press("v"))
            #expect(fixture.textView.string == "one two")
        }
        withFixture(.practice, "one\ntw|o three") { fixture in
            for character in ["d", "l", "h"] {
                #expect(!fixture.press(character))
                #expect(fixture.textView.string == "one\ntwo three")
                #expect(fixture.textView.selectedRange() == NSRange(location: 6, length: 0))
            }
        }
    }

    @Test("AC-13: ⌘Z で直前の切り取りが戻り、⇧⌘Z でやり直される")
    func undoAndRedoAreHandled() {
        let cases: [(Kind, String, String, String)] = [
            (.panel, "alpha\nbe|ta\ngamma", "alpha\nbeta\ngamma", "alpha\ngamma"),
            (.practice, "[one] two", "one two", " two"),
        ]
        for (kind, marked, original, cut) in cases {
            withFixture(kind, marked) { fixture in
                #expect(fixture.press("x"))
                #expect(fixture.textView.string == cut)

                #expect(fixture.press("z"))
                #expect(fixture.textView.string == original)

                #expect(fixture.press("z", modifiers: [.command, .shift]))
                #expect(fixture.textView.string == cut)
            }
        }
    }

    // MARK: - AC-14

    @Test("AC-14: 「ショートカットキー」の一覧は今と同じ7行で、並び・キー・説明が同じ")
    func shortcutListing() {
        let expected: [(id: String, keys: String, action: String)] = [
            ("moveLine", "⌥↑ / ⌥↓", "行を上 / 下の行と入れ替える"),
            ("duplicateLine", "⇧⌥↑ / ⇧⌥↓", "行を下に複製する"),
            ("copyLine", "⌘C", "選択なしで行ごとコピー"),
            ("cutLine", "⌘X", "選択なしで行ごと切り取り"),
            ("pasteLine", "⌘V", "行ごとコピー・切り取りした行を上に貼り付け"),
            ("selectLine", "⌘L", "行を選択(続けて押すと下へ広げる)"),
            ("selectWord", "⌘D", "カーソルのある単語を選択"),
        ]
        let rows = EditorShortcuts.all
        #expect(rows.count == expected.count)
        for (row, want) in zip(rows, expected) {
            #expect(row.id == want.id)
            #expect(row.keys == want.keys)
            #expect(row.action == want.action)
        }
        #expect(EditorKeyCommand.selectAll.listing == nil)
        #expect(EditorKeyCommand.undo.listing == nil)
        #expect(EditorKeyCommand.redo.listing == nil)
    }

    // MARK: - AC-15

    @Test("AC-15: 編集キー(⌘A・⌘C・⌘D・⌘H・⌘L・⌘V・⌘X・⌘Z・⇧⌘Z・⌥↑・⌥↓・⇧⌥↑・⇧⌥↓)は記録ボックスで拒否される")
    func editingKeysAreRejected() {
        let reserved: [PanelShortcutCandidate] = [
            candidate(0, [.command], "a"),
            candidate(8, [.command], "c"),
            candidate(2, [.command], "d"),
            candidate(4, [.command], "h"),
            candidate(37, [.command], "l"),
            candidate(9, [.command], "v"),
            candidate(7, [.command], "x"),
            candidate(6, [.command], "z"),
            candidate(6, [.command, .shift], "z"),
            candidate(126, [.option], ""),
            candidate(125, [.option], ""),
            candidate(126, [.shift, .option], ""),
            candidate(125, [.shift, .option], ""),
        ]
        for key in reserved {
            #expect(rejection(for: key) == .reservedForEditing)
        }
    }

    @Test("AC-15: ⌃⌘C・⌥⌘V・⌘B・⇧⌘C は編集キーとしては拒否されない")
    func otherKeysAreNotRejectedAsEditing() {
        let allowed: [PanelShortcutCandidate] = [
            candidate(8, [.control, .command], "c"),
            candidate(9, [.option, .command], "v"),
            candidate(11, [.command], "b"),
            candidate(8, [.command, .shift], "c"),
        ]
        for key in allowed {
            #expect(rejection(for: key) != .reservedForEditing)
        }
        #expect(EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command], character: "h"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command], character: "b"))
    }
}
