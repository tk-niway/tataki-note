import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsWindowModelTests {
    @Test("AC-9: 設定画面は「一般」を選んだ状態で始まり、どの項目を選んでいても開き直すと「一般」に戻る")
    func startsAndReopensWithGeneral() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .general)

        for section in SettingsSection.allCases {
            model.selectedSection = section
            model.prepareForOpen()
            #expect(model.selectedSection == .general, "\(section)")
        }
    }

    @Test("サイドバーの項目は「一般」から始まり、表示名は「一般」、アイコンは gearshape、識別子に使う値は general")
    func sidebarSections() {
        #expect(SettingsSection.allCases.first == .general)
        #expect(SettingsSection.general.displayName == "一般")
        #expect(SettingsSection.general.systemImage == "gearshape")
        #expect(SettingsSection.general.rawValue == "general")
        #expect(SettingsSection.general.id == .general)
    }

    @Test("AC-28: 案内の「インサートに切り替える →」とサイドバーの「インサート」が通る selectAppMode(_:in:) は、確定キーが両方未登録なら注入したホットキー以外の初期値を登録してインサートモードにする")
    func selectAppModeRegistersDefaultKeysThroughInjectedHotkey() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = nil
        settings.commitAndSendKey = nil
        settings.selectAppMode(.note, hotkey: nil)
        let model = SettingsWindowModel(hotkey: { .commandShiftReturn })

        model.selectAppMode(.insert, in: settings)

        #expect(settings.appMode == .insert)
        #expect(settings.commitKey == nil)
        #expect(settings.commitAndSendKey == PanelShortcut.defaultCommitAndSendKey)
    }

    @Test("selectAppMode は今と同じモードを選んでも何も変えない")
    func selectAppModeIgnoresSameMode() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.selectAppMode(.note, hotkey: nil)
        settings.commitKey = nil
        settings.commitAndSendKey = nil
        let model = SettingsWindowModel(hotkey: { nil })

        model.selectAppMode(.note, in: settings)

        #expect(settings.appMode == .note)
        #expect(settings.commitKey == nil)
        #expect(settings.commitAndSendKey == nil)
    }
}
