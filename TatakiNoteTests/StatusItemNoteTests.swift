import Testing
@testable import TatakiNote

@MainActor
struct StatusItemNoteTests {
    @Test("AC-26: 確定キーが両方登録済みなら、どの項目にも注記は付かない")
    func noNoteWhenKeysAreRegistered() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        let model = EditorSettingsModel(settings: settings)

        for item in PanelStatusItem.allCases {
            #expect(model.statusItemNote(item) == nil, "\(item)")
        }
    }

    @Test("AC-26: 確定+挿入キーが未登録なら、その項目にだけ「キーを登録していない」注記が付く")
    func commitKeyNotAssignedNotesOnlyCommit() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        let model = EditorSettingsModel(settings: settings)

        settings.selectCommitKey(nil)

        for item in PanelStatusItem.allCases {
            let expected: StatusItemNote? = item == .commit ? .keyNotAssigned : nil
            #expect(model.statusItemNote(item) == expected, "\(item)")
        }
    }

    @Test("AC-26: 確定+送信キーが未登録なら、その項目にだけ注記が付く。帯に出さない設定でも変わらない")
    func commitAndSendKeyNotAssignedNotesOnlyCommitAndSend() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        let model = EditorSettingsModel(settings: settings)

        settings.selectCommitAndSendKey(nil)
        model.setStatusItem(.commitAndSend, isVisible: false)

        for item in PanelStatusItem.allCases {
            let expected: StatusItemNote? = item == .commitAndSend ? .keyNotAssigned : nil
            #expect(model.statusItemNote(item) == expected, "\(item)")
        }
    }
}
