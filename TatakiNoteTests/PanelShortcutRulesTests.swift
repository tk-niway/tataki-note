import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelShortcutRulesTests {
    private func candidate(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String) -> PanelShortcutCandidate {
        PanelShortcutCandidate(shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers), characters: characters)
    }

    @Test("AC-12: 修飾キーを含まないキーは missingModifier")
    func missingModifierIsRejected() {
        let rejection = PanelShortcutRules.rejection(
            for: candidate(keyCode: 40, modifiers: [], characters: "k"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(rejection == .missingModifier)
    }

    @Test("AC-30: 修飾キー付きの Esc(⇧Esc・⌘Esc)は reservedForClosing。修飾キーなしの Esc はここまで来ず missingModifier")
    func escapeWithModifierIsReservedForClosing() {
        for modifiers: NSEvent.ModifierFlags in [[.shift], [.command], [.command, .shift]] {
            let rejection = PanelShortcutRules.rejection(
                for: candidate(keyCode: 53, modifiers: modifiers, characters: "\u{1b}"),
                role: .commit,
                hotkey: nil,
                commitKey: nil,
                commitAndSendKey: nil
            )
            #expect(rejection == .reservedForClosing, "\(modifiers)")
        }
        let withoutModifier = PanelShortcutRules.rejection(
            for: candidate(keyCode: 53, modifiers: [], characters: "\u{1b}"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(withoutModifier == .missingModifier)
    }

    @Test("AC-15: 入力欄の編集ショートカット(⌘A・⌘C・⌘D・⌘H・⌘L・⌘V・⌘X・⌘Z・⇧⌘Z・⌥↑・⌥↓・⇧⌥↑・⇧⌥↓)は reservedForEditing")
    func editingShortcutsAreReserved() {
        let commandLetters: [(UInt16, String)] = [
            (0, "a"), (8, "c"), (2, "d"), (4, "h"), (37, "l"), (9, "v"), (7, "x"), (6, "z"),
        ]
        for (keyCode, characters) in commandLetters {
            let rejection = PanelShortcutRules.rejection(
                for: candidate(keyCode: keyCode, modifiers: [.command], characters: characters),
                role: .commit,
                hotkey: nil,
                commitKey: nil,
                commitAndSendKey: nil
            )
            #expect(rejection == .reservedForEditing, "⌘\(characters)")
        }

        let shiftCommandZ = PanelShortcutRules.rejection(
            for: candidate(keyCode: 6, modifiers: [.command, .shift], characters: "z"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(shiftCommandZ == .reservedForEditing)

        let arrowCases: [(UInt16, NSEvent.ModifierFlags)] = [
            (126, [.option]), (125, [.option]), (126, [.option, .shift]), (125, [.option, .shift]),
        ]
        for (keyCode, modifiers) in arrowCases {
            let rejection = PanelShortcutRules.rejection(
                for: candidate(keyCode: keyCode, modifiers: modifiers, characters: ""),
                role: .commit,
                hotkey: nil,
                commitKey: nil,
                commitAndSendKey: nil
            )
            #expect(rejection == .reservedForEditing, "\(keyCode) \(modifiers)")
        }
    }

    @Test("AC-15: 編集ショートカットでない ⌘ の文字(⌘K など)は reservedForEditing にならない")
    func nonEditingCommandLetterIsNotReserved() {
        let rejection = PanelShortcutRules.rejection(
            for: candidate(keyCode: 40, modifiers: [.command], characters: "k"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(rejection == nil)
    }

    @Test("AC-13: ホットキーと同じキーは usedByHotkey。ホットキーが nil のときは当たらない")
    func hotkeyCollisionIsRejected() {
        let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        let rejection = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: hotkey, characters: " "),
            role: .commit,
            hotkey: hotkey,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(rejection == .usedByHotkey)

        let noHotkey = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: hotkey, characters: " "),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(noHotkey == nil)
    }

    @Test("AC-14: 確定キーで使っているキーを確定+送信キーに押しても(逆も)usedByOtherRole")
    func otherRoleCollisionIsRejected() {
        let key = PanelShortcut(keyCode: 40, modifiers: [.command])

        let commitAndSendUsesIt = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: key, characters: "k"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: key
        )
        #expect(commitAndSendUsesIt == .usedByOtherRole(.commitAndSend))

        let commitUsesIt = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: key, characters: "k"),
            role: .commitAndSend,
            hotkey: nil,
            commitKey: key,
            commitAndSendKey: nil
        )
        #expect(commitUsesIt == .usedByOtherRole(.commit))
    }

    @Test("AC-14: 自分の役割に今登録してあるキーと同じキーは受け付ける(値が変わらないので拒まない)")
    func sameRoleCurrentKeyIsAccepted() {
        let key = PanelShortcut(keyCode: 40, modifiers: [.command])
        let rejection = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: key, characters: "k"),
            role: .commit,
            hotkey: nil,
            commitKey: key,
            commitAndSendKey: nil
        )
        #expect(rejection == nil)
    }

    @Test("順: ホットキーともう一方の両方に同じキーが登録されていても、先に usedByHotkey になる")
    func hotkeyRejectionTakesPrecedenceOverOtherRole() {
        let key = PanelShortcut(keyCode: 40, modifiers: [.command])
        let rejection = PanelShortcutRules.rejection(
            for: PanelShortcutCandidate(shortcut: key, characters: "k"),
            role: .commit,
            hotkey: key,
            commitKey: nil,
            commitAndSendKey: key
        )
        #expect(rejection == .usedByHotkey)
    }

    @Test("修飾キーを含み、どの理由にも当たらないキー(例 ⌘Q)は受け付ける")
    func unreservedShortcutIsAccepted() {
        let rejection = PanelShortcutRules.rejection(
            for: candidate(keyCode: 12, modifiers: [.command], characters: "q"),
            role: .commit,
            hotkey: nil,
            commitKey: nil,
            commitAndSendKey: nil
        )
        #expect(rejection == nil)
    }
}
