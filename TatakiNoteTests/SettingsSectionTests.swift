import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct SettingsSectionTests {
    @Test("AC-1: サイドバーの項目は「一般」「キー」「パネル」「アプリ情報」の順で、表示名・アイコン・識別子に使う値が決まっていて、「エディタ設定」は無い")
    func sidebarSectionsInOrder() {
        #expect(SettingsSection.allCases == [.general, .keys, .panel, .appInfo])
        #expect(SettingsSection.allCases.map(\.displayName) == ["一般", "キー", "パネル", "アプリ情報"])
        #expect(SettingsSection.allCases.map(\.systemImage) == ["gearshape", "keyboard", "macwindow", "info.circle"])
        #expect(SettingsSection.allCases.map(\.rawValue) == ["general", "keys", "panel", "appInfo"])
        #expect(!SettingsSection.allCases.map(\.displayName).contains("エディタ設定"))
    }

    @Test("AC-2: 設定画面は「一般」を選んだ状態で始まり、「キー」「パネル」「アプリ情報」のどれを選んでいても開き直すと「一般」に戻る")
    func opensWithGeneral() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .general)

        for section in [SettingsSection.keys, .panel, .appInfo] {
            model.selectedSection = section
            model.prepareForOpen()
            #expect(model.selectedSection == .general, "\(section)")
        }
    }

    @Test("AC-2: 「キー」「パネル」「アプリ情報」のどれを出したまま設定画面の窓を閉じても「一般」に戻る")
    func closingWindowReturnsToGeneral() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil })
        )

        for section in [SettingsSection.keys, .panel, .appInfo] {
            controller.model.selectedSection = section

            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

            #expect(controller.model.selectedSection == .general, "\(section)")
        }
    }
}
