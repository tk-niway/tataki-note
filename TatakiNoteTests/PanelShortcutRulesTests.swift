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

    @Test("AC-3, AC-5: 確定+挿入キーの説明文は、初期値が ⇧⌘↩ と伝える全文になる")
    func commitDescriptionStatesNewDefault() {
        #expect(PanelShortcutRole.commit.settingDescription == "パネルでこのキーを押すと、書いた文章を元のアプリに挿入します(送信はしません)。修飾キー(⌘・⌥・⌃・⇧)と組み合わせたキーを登録できます。登録していない Enter は改行になります。初期値は ⇧⌘↩ です。登録していないときは、確定+送信キーでだけ挿入します。")
    }

    @Test("AC-3, AC-5: 確定+送信キーの説明文は、初期値が ⌘↩ と伝え、確定+挿入キーを使うよう勧める全文になる")
    func commitAndSendDescriptionDoesNotAskToRegisterCommitKey() {
        #expect(PanelShortcutRole.commitAndSend.settingDescription == "パネルでこのキーを押すと、書いた文章を挿入したあと、挿入先で Enter を送って送信します。初期値は ⌘↩ です。送信は取り消せないので、送信せずに挿入したいときは確定+挿入キーを使ってください。")
    }

    @Test("AC-3: 説明文の初期値は役割の初期値の定数から出し、渡したキーに従って変わる(登録なしは「登録なし」)")
    func descriptionFollowsInitialKey() {
        #expect(PanelShortcutRole.commit.initialKey == PanelShortcut.defaultCommitKey)
        #expect(PanelShortcutRole.commitAndSend.initialKey == PanelShortcut.defaultCommitAndSendKey)

        let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
        for role in PanelShortcutRole.allCases {
            let withKey = role.settingDescription(initialKey: commandK)
            #expect(withKey.contains("初期値は ⌘K です。"))
            let withoutKey = role.settingDescription(initialKey: nil)
            #expect(withoutKey.contains("初期値は 登録なし です。"))
        }
    }

    @Test("AC-4: もう一方のキーとぶつかったときの理由は、ぶつかった役割を「確定+挿入キー」「確定+送信キー」と呼ぶ")
    func otherRoleMessageNamesTheRole() {
        let key = PanelShortcut(keyCode: 40, modifiers: [.command])
        #expect(
            PanelShortcutRejection.usedByOtherRole(.commit).message(for: key)
                == "⌘K は「確定+挿入キー」で使っているため、登録できません。"
        )
        #expect(
            PanelShortcutRejection.usedByOtherRole(.commitAndSend).message(for: key)
                == "⌘K は「確定+送信キー」で使っているため、登録できません。"
        )
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
