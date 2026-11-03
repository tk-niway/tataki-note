import AppKit
import Testing
@testable import TatakiNote

struct PanelHideKeyTests {
    private func candidate(_ modifiers: NSEvent.ModifierFlags, _ characters: String) -> PanelShortcutCandidate {
        PanelShortcutCandidate(shortcut: PanelShortcut(keyCode: 4, modifiers: modifiers), characters: characters)
    }

    private func isRejectedForHiding(_ modifiers: NSEvent.ModifierFlags, _ characters: String) -> Bool {
        PanelShortcutRules.rejection(
            for: candidate(modifiers, characters),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        ) == .reservedForHiding
    }

    @Test("AC-6: ⌘H はパネルで拾う判定に当たり、Caps Lock 付きも当たる")
    func panelMatchesCommandH() {
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "h"))
        #expect(PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "H"))
        #expect(PanelHideKey.matches(modifiers: [.command, .capsLock], charactersIgnoringModifiers: "h"))
    }

    @Test("AC-6: ⇧⌘H・⌥⌘H・H だけ・⌘J・文字なしはパネルで拾う判定に当たらない")
    func panelRejectsOthers() {
        #expect(!PanelHideKey.matches(modifiers: [.command, .shift], charactersIgnoringModifiers: "h"))
        #expect(!PanelHideKey.matches(modifiers: [.command, .option], charactersIgnoringModifiers: "h"))
        #expect(!PanelHideKey.matches(modifiers: [], charactersIgnoringModifiers: "h"))
        #expect(!PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: "j"))
        #expect(!PanelHideKey.matches(modifiers: [.command], charactersIgnoringModifiers: nil))
    }

    @Test("AC-6: 記録で ⌘H を断り、⇧⌘H・⌥⌘H・H だけ・⌘J は断らない")
    func recordingRejectsCommandHOnly() {
        #expect(isRejectedForHiding([.command], "h"))
        #expect(!isRejectedForHiding([.command, .shift], "h"))
        #expect(!isRejectedForHiding([.command, .option], "h"))
        #expect(!isRejectedForHiding([.command], "j"))
    }

    @Test("AC-6: 入力欄の予約の判定が ⌘H に当たり、Caps Lock 付きも当たる")
    func editorReservesCommandH() {
        #expect(EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command], character: "h"))
        #expect(EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command, .capsLock], character: "h"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command], character: "H"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command, .shift], character: "h"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command, .option], character: "h"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [], character: "h"))
        #expect(!EditorKeyCommand.isReservedKeyEquivalent(modifiers: [.command], character: "j"))
    }

    @Test("AC-6: ⌘H の定義は1か所で、3つの判定が同じキーを使う")
    func singleDefinition() {
        let key = PanelHideKey.key
        #expect(key == EditorKeyEquivalent(modifiers: [.command], character: "h"))
        #expect(PanelHideKey.matches(modifiers: key.modifiers, charactersIgnoringModifiers: key.character))
        #expect(isRejectedForHiding(key.modifiers, key.character))
        #expect(EditorKeyCommand.isReservedKeyEquivalent(modifiers: key.modifiers, character: key.character))
    }
}
