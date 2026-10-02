import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelShortcutTests {
    @Test("AC-33: 修飾キーは relevantModifiers(⌘⌥⌃⇧)だけに絞られ、Caps Lock・fn・テンキーの印は含めない")
    func modifiersAreLimitedToRelevantOnes() {
        let shortcut = PanelShortcut(
            keyCode: 40,
            modifiers: [.command, .capsLock, .function, .numericPad]
        )
        #expect(shortcut.modifiers == [.command])
    }

    @Test("AC-18: テンキーの Enter(76)は Return(36)にそろえる")
    func keypadEnterIsNormalizedToReturn() {
        let shortcut = PanelShortcut(keyCode: 76, modifiers: [.command])
        #expect(shortcut.keyCode == 36)
        #expect(shortcut == PanelShortcut.commandReturn)
    }

    @Test("AC-18: matches はキーコード(テンキーの Enter を含む)と relevantModifiers に絞った修飾キーが同じときだけ true")
    func matchesComparesNormalizedKeyCodeAndModifiers() {
        let shortcut = PanelShortcut.commandReturn
        #expect(shortcut.matches(PanelKeyInput(keyCode: 36, modifiers: [.command], hasMarkedText: false)))
        #expect(shortcut.matches(PanelKeyInput(keyCode: 76, modifiers: [.command], hasMarkedText: false)))
        #expect(shortcut.matches(PanelKeyInput(keyCode: 36, modifiers: [.command, .capsLock], hasMarkedText: false)))
        #expect(!shortcut.matches(PanelKeyInput(keyCode: 36, modifiers: [.command, .shift], hasMarkedText: false)))
        #expect(!shortcut.matches(PanelKeyInput(keyCode: 40, modifiers: [.command], hasMarkedText: false)))

        let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
        #expect(commandK.matches(PanelKeyInput(keyCode: 40, modifiers: [.command], hasMarkedText: false)))
        #expect(!commandK.matches(PanelKeyInput(keyCode: 40, modifiers: [.command, .shift], hasMarkedText: false)))
    }

    @Test("AC-12: 修飾キーを含まないキーは hasModifier が false、含むキーは true")
    func hasModifierReflectsWhetherAnyModifierIsSet() {
        #expect(PanelShortcut(keyCode: 40, modifiers: []).hasModifier == false)
        #expect(PanelShortcut(keyCode: 40, modifiers: [.command]).hasModifier)
        #expect(PanelShortcut(keyCode: 40, modifiers: [.option]).hasModifier)
    }

    @Test("AC-11: storedValue と init?(storedValue:) は往復できる")
    func storedValueRoundTrips() {
        let cases: [PanelShortcut] = [
            .commandReturn,
            .shiftReturn,
            .commandShiftReturn,
            PanelShortcut(keyCode: 40, modifiers: [.command]),
            PanelShortcut(keyCode: 36, modifiers: [.option]),
        ]
        for shortcut in cases {
            let restored = PanelShortcut(storedValue: shortcut.storedValue)
            #expect(restored == shortcut, "\(shortcut)")
        }
        #expect(PanelShortcut.commandReturn.storedValue == [36, 1_048_576])
    }

    @Test("AC-22: 壊れた配列(要素数が2でない・整数でない・真偽値・修飾キーが relevantModifiers の外・修飾キーが無い)は nil")
    func brokenStoredValuesFailToInitialize() {
        let cases: [[Any]] = [
            [],
            [36],
            [36, 1_048_576, 0],
            ["36", 1_048_576],
            [36, "1048576"],
            [true, 1_048_576],
            [36, true],
            [36, 0],
            [36, NSEvent.ModifierFlags.function.rawValue],
            [36, -1],
            [36.5, 1_048_576],
        ]
        for value in cases {
            #expect(PanelShortcut(storedValue: value) == nil, "\(value)")
        }
    }

    @Test("AC-22: 修飾キーに relevantModifiers 以外のビット(Caps Lock など)が混ざっていれば nil(relevantModifiers の中だけで1つ以上のときだけ値)")
    func storedValueRejectsModifiersOutsideRelevantSet() {
        let mixed = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.capsLock.rawValue
        let shortcut = PanelShortcut(storedValue: [40, Int(mixed)])
        #expect(shortcut == nil)
    }

    @Test("AC-9, AC-33: 新しい初期値は確定が登録なし・確定+送信が ⌘↩、以前の初期値は確定が ⌘↩・確定+送信が登録なし")
    func defaultAndLegacyDefaultValues() {
        #expect(PanelShortcut.defaultCommitKey == nil)
        #expect(PanelShortcut.defaultCommitAndSendKey == .commandReturn)
        #expect(PanelShortcut.legacyDefaultCommitKey == .commandReturn)
        #expect(PanelShortcut.legacyDefaultCommitAndSendKey == nil)
    }

    @Test("AC-20: displayText は ⌘↩・⇧↩・⇧⌘↩ になる")
    func displayTextMatchesKnownShortcuts() {
        #expect(PanelShortcut.commandReturn.displayText == "⌘↩")
        #expect(PanelShortcut.shiftReturn.displayText == "⇧↩")
        #expect(PanelShortcut.commandShiftReturn.displayText == "⇧⌘↩")
    }
}
