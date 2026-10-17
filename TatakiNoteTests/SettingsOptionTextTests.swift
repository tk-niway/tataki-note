import Testing
@testable import TatakiNote

struct SettingsOptionTextTests {
    @Test("AC-37: 押せないのはノートモードの「入力欄の近く」だけ")
    func onlyNearFocusedFieldInNoteModeIsNotSelectable() {
        let expected: [(PanelScreen, Bool, Bool)] = [
            (.nearFocusedField, false, true),
            (.targetWindow, false, true),
            (.mouse, false, true),
            (.main, false, true),
            (.nearFocusedField, true, false),
            (.targetWindow, true, true),
            (.mouse, true, true),
            (.main, true, true),
        ]
        #expect(expected.count == PanelScreen.allCases.count * 2)
        for (screen, isNoteMode, isSelectable) in expected {
            #expect(screen.isSelectable(isNoteMode: isNoteMode) == isSelectable, "\(screen) note=\(isNoteMode)")
        }
    }
}
