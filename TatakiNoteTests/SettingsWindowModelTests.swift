import Testing
@testable import TatakiNote

@MainActor
struct SettingsWindowModelTests {
    @Test("AC-2: 設定画面は「一般」を選んだ状態で始まり、どの項目を選んでいても開き直すと「一般」に戻る")
    func startsAndReopensWithGeneral() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .general)

        for section in SettingsSection.allCases {
            model.selectedSection = section
            model.prepareForOpen()
            #expect(model.selectedSection == .general, "\(section)")
        }
    }

    @Test("AC-1: サイドバーの項目は「一般」から始まり、表示名は「一般」、アイコンは gearshape、識別子に使う値は general")
    func sidebarSections() {
        #expect(SettingsSection.allCases.first == .general)
        #expect(SettingsSection.general.displayName == "一般")
        #expect(SettingsSection.general.systemImage == "gearshape")
        #expect(SettingsSection.general.rawValue == "general")
        #expect(SettingsSection.general.id == .general)
    }
}
