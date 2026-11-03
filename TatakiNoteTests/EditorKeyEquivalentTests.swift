import AppKit
import Testing
@testable import TatakiNote

struct EditorKeyEquivalentTests {
    private let commandS = EditorKeyEquivalent(modifiers: [.command], character: "s")
    private let shiftCommandS = EditorKeyEquivalent(modifiers: [.command, .shift], character: "s")

    @Test("AC-5: 押した修飾キーと文字が同じなら当たる")
    func matchesSameKey() {
        #expect(commandS.matches(modifiers: [.command], character: "s"))
        #expect(shiftCommandS.matches(modifiers: [.command, .shift], character: "s"))
    }

    @Test("AC-5: Caps Lock・fn・テンキーの印は無視する")
    func ignoresIrrelevantModifiers() {
        #expect(commandS.matches(modifiers: [.command, .capsLock], character: "s"))
        #expect(commandS.matches(modifiers: [.command, .function], character: "s"))
        #expect(commandS.matches(modifiers: [.command, .numericPad], character: "s"))
    }

    @Test("AC-5: 修飾キーの過不足は当たらない")
    func rejectsModifierMismatch() {
        #expect(!commandS.matches(modifiers: [.command, .shift], character: "s"))
        #expect(!commandS.matches(modifiers: [.command, .option], character: "s"))
        #expect(!commandS.matches(modifiers: [], character: "s"))
        #expect(!shiftCommandS.matches(modifiers: [.command], character: "s"))
    }

    @Test("AC-5: 文字は完全一致で、大文字と空は当たらない")
    func rejectsCharacterMismatch() {
        #expect(!commandS.matches(modifiers: [.command], character: "S"))
        #expect(!commandS.matches(modifiers: [.command], character: ""))
        #expect(!commandS.matches(modifiers: [.command], character: "k"))
    }

    @Test("AC-5: パネルが拾うキーと操作になるキーは同じ関数で決まる")
    func reservedAndRowAgree() {
        let modifierSets: [NSEvent.ModifierFlags] = [
            [], [.command], [.command, .shift], [.command, .option], [.command, .capsLock], [.command, .function],
        ]
        let characters = ["k", "s", "n", "e", "b", ",", "h", "S", ""]
        for modifiers in modifierSets {
            for character in characters {
                let isReserved = ReservedPanelKeys.contains(modifiers: modifiers, character: character)
                let row = PanelCommandKeys.row(modifiers: modifiers, character: character)
                #expect(isReserved == (row != nil), "\(modifiers.rawValue) \(character)")
            }
        }
        for row in PanelCommandKeys.all {
            #expect(PanelCommandKeys.row(modifiers: row.key.modifiers, character: row.key.character)?.action == row.action)
            #expect(ReservedPanelKeys.contains(modifiers: row.key.modifiers, character: row.key.character))
        }
    }
}
