import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelShortcutRecorderInputTests {
    @Test("AC-27: 修飾キーなしの Esc は記録をやめる(cancel)")
    func unmodifiedEscapeCancels() {
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.escape, modifiers: []) == .cancel)
    }

    @Test("修飾キー付きの Esc(⇧Esc・⌘Esc)は記録に回す(規則が拒む)")
    func modifiedEscapeIsRecorded() {
        for modifiers: NSEvent.ModifierFlags in [[.shift], [.command], [.command, .shift]] {
            #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.escape, modifiers: modifiers) == .record, "\(modifiers)")
        }
    }

    @Test("修飾キーなしの Delete・Forward Delete は登録を消す(clear)")
    func unmodifiedDeleteClears() {
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.delete, modifiers: []) == .clear)
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.forwardDelete, modifiers: []) == .clear)
    }

    @Test("修飾キー付きの Delete・Forward Delete(⌘Delete など)は記録に回す")
    func modifiedDeleteIsRecorded() {
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.delete, modifiers: [.command]) == .record)
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.forwardDelete, modifiers: [.option]) == .record)
    }

    @Test("それ以外のキー(文字キー・Return・Tab など)は記録に回す")
    func otherKeysAreRecorded() {
        #expect(PanelShortcutRecorderInput.action(keyCode: 40, modifiers: []) == .record)
        #expect(PanelShortcutRecorderInput.action(keyCode: 40, modifiers: [.command]) == .record)
        #expect(PanelShortcutRecorderInput.action(keyCode: KeyCode.returnKey, modifiers: []) == .record)
        #expect(PanelShortcutRecorderInput.action(keyCode: 48, modifiers: []) == .record)
    }

    @Test("AC-27: isOutsideClick は、別の窓なら常に外")
    func outsideClickAcrossWindows() {
        let bounds = CGRect(x: 0, y: 0, width: 160, height: 22)
        #expect(PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: 80, y: 11), recorderBounds: bounds, isSameWindow: false))
    }

    @Test("AC-27: isOutsideClick は、同じ窓で記録ボックスの枠(少し広げた範囲)の外なら外")
    func outsideClickWithinSameWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 160, height: 22)
        #expect(!PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: 80, y: 11), recorderBounds: bounds, isSameWindow: true))
        #expect(!PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: -1, y: 11), recorderBounds: bounds, isSameWindow: true))
        #expect(!PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: 161, y: 11), recorderBounds: bounds, isSameWindow: true))
        #expect(PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: -10, y: 11), recorderBounds: bounds, isSameWindow: true))
        #expect(PanelShortcutRecorderInput.isOutsideClick(location: CGPoint(x: 80, y: 100), recorderBounds: bounds, isSameWindow: true))
    }
}
