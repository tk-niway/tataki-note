import Testing
@testable import TatakiNote

@MainActor
struct PanelActionKeyTests {
    @Test("AC-10: 以前の形式(shiftEnter・commandEnter・commandShiftEnter・none)は、それぞれ ⇧↩・⌘↩・⇧⌘↩・登録なし(nil)に読み替わる")
    func shortcutTranslatesLegacyValues() {
        #expect(PanelActionKey.shiftEnter.shortcut == .shiftReturn)
        #expect(PanelActionKey.commandEnter.shortcut == .commandReturn)
        #expect(PanelActionKey.commandShiftEnter.shortcut == .commandShiftReturn)
        #expect(PanelActionKey.none.shortcut == nil)
    }
}
