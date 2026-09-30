import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct SettingsSectionTests {
    @Test("AC-1: サイドバーの項目は「一般」「エディタ設定」「アプリ情報」の順で、表示名・アイコン・識別子に使う値が決まっている")
    func sidebarSectionsInOrder() {
        #expect(SettingsSection.allCases == [.general, .editor, .appInfo])
        #expect(SettingsSection.allCases.map(\.displayName) == ["一般", "エディタ設定", "アプリ情報"])
        #expect(SettingsSection.allCases.map(\.systemImage) == ["gearshape", "textformat", "info.circle"])
        // @note p0-1047
        #expect(SettingsSection.allCases.map(\.rawValue) == ["general", "editor", "appInfo"])
    }

    @Test("AC-1: 設定画面は「一般」を選んだ状態で始まり、「エディタ設定」「アプリ情報」を選んでいても開き直すと「一般」に戻る")
    func opensWithGeneral() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .general)

        for section in [SettingsSection.editor, .appInfo] {
            model.selectedSection = section
            model.prepareForOpen()
            #expect(model.selectedSection == .general, "\(section)")
        }
    }

    @Test("AC-10: 「アプリ情報」を出したまま設定画面の窓を閉じると「一般」に戻る(アプリ情報の画面が外れ、許可の確かめ直しが止まる)")
    func closingWindowReturnsToGeneral() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        // @note p0-1048
        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil })
        )
        controller.model.selectedSection = .appInfo

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(controller.model.selectedSection == .general)
    }
}
