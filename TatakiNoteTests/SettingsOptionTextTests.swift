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

    @Test("ノートモードでの案内は、自動表示と挿入・送信で別の文になる")
    func noteModeMessagesDiffer() {
        #expect(InsertOnlyGroup.autoShow.noteModeMessage == "ノートモードでは自動表示しません")
        #expect(InsertOnlyGroup.insertAndSend.noteModeMessage == "ノートモードでは挿入・送信しません")
    }
}
