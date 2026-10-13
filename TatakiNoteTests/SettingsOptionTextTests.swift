import Testing
@testable import TatakiNote

struct SettingsOptionTextTests {
    @Test("AC-37: 選択肢ごとの説明は、入力欄の位置が分からないとき・挿入先のウィンドウが分からないとき・メインの画面の意味を落とさない")
    func optionDescriptionsKeepTheirMeaning() {
        #expect(PanelScreen.nearFocusedField.optionDescription.contains("入力欄の位置が分からないとき"))
        #expect(PanelScreen.nearFocusedField.optionDescription.contains("挿入先のウィンドウがある画面の中央"))
        #expect(PanelScreen.targetWindow.optionDescription.contains("挿入先のウィンドウが分からないとき"))
        #expect(PanelScreen.targetWindow.optionDescription.contains("マウスのある画面"))
        #expect(PanelScreen.mouse.optionDescription.contains("マウスポインタのすぐ下"))
        #expect(PanelScreen.main.optionDescription.contains("メインディスプレイ"))
    }

    @Test("AC-37: タイルの下の説明は、前置きに選んでいる1つの説明を続けた文になる")
    func settingDescriptionJoinsLeadAndSelected() {
        #expect(PanelScreen.settingLead == "パネルを新しく開くときに出す位置です。")
        for screen in PanelScreen.allCases {
            #expect(PanelScreen.settingDescription(selected: screen) == PanelScreen.settingLead + screen.optionDescription, "\(screen)")
            let others = PanelScreen.allCases.filter { $0 != screen }
            for other in others {
                #expect(!PanelScreen.settingDescription(selected: screen).contains(other.optionDescription), "\(screen) \(other)")
            }
        }
    }

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
