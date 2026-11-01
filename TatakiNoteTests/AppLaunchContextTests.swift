import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppLaunchContextTests {
    @Test("AC-8: テストの環境変数があるとき(単体テストのホスト)はホットキーを登録しない")
    func unitTestHostDoesNotRegisterHotkeys() {
        let environments: [[String: String]] = [
            ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"],
            ["XCTestBundlePath": "/tmp/TatakiNoteTests.xctest"],
            ["XCTestConfigurationFilePath": "/tmp/a", "XCTestBundlePath": "/tmp/b", "HOME": "/Users/test"],
        ]

        for environment in environments {
            #expect(AppLaunchContext.isRunningUnitTests(environment: environment) == true, "\(environment)")
            #expect(AppLaunchContext.shouldRegisterHotkeys(environment: environment) == false, "\(environment)")
        }
    }

    @Test("AC-8: テストの環境変数が無い起動(通常・UI テスト)ではホットキーを登録する")
    func otherLaunchesRegisterHotkeys() {
        let environments: [[String: String]] = [
            [:],
            ["HOME": "/Users/test", "PATH": "/usr/bin"],
            ["XCTestSessionIdentifier": "abc", "XCTestManagerVariant": "DDI"],
        ]

        for environment in environments {
            #expect(AppLaunchContext.isRunningUnitTests(environment: environment) == false, "\(environment)")
            #expect(AppLaunchContext.shouldRegisterHotkeys(environment: environment) == true, "\(environment)")
        }
    }

    // MARK: - 設定の保存先

    @Test("AC-12: DEBUG で TATAKINOTE_SETTINGS_SUITE があればその名前、空・無しなら指定なし")
    func settingsSuiteName() {
        #expect(AppLaunchContext.settingsSuiteName(environment: ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc"]) == "TatakiNoteUITests.abc")
        #expect(
            AppLaunchContext.settingsSuiteName(environment: ["TATAKINOTE_SETTINGS_SUITE": "x", "HOME": "/Users/test"]) == "x"
        )

        let withoutSuite: [[String: String]] = [
            [:],
            ["TATAKINOTE_SETTINGS_SUITE": ""],
            ["HOME": "/Users/test", "XCTestSessionIdentifier": "abc"],
            ["tatakinote_settings_suite": "lowercase"],
        ]
        for environment in withoutSuite {
            #expect(AppLaunchContext.settingsSuiteName(environment: environment) == nil, "\(environment)")
        }
    }

    @Test("AC-14: suite の指定があれば、その名前の suite に保存し、標準の保存先は使わない")
    func settingsDefaultsUsesNamedSuite() throws {
        let name = UUID().uuidString
        let suite = try #require(InMemoryDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        var requestedNames: [String] = []
        let defaults = AppLaunchContext.settingsDefaults(environment: ["TATAKINOTE_SETTINGS_SUITE": name]) { requested in
            requestedNames.append(requested)
            return suite
        }

        #expect(requestedNames == [name])
        #expect(defaults === suite)
        #expect(defaults !== UserDefaults.standard)

        SettingsStore(defaults: defaults).saveCommitShortcut(.commandReturn)
        SettingsStore(defaults: defaults).savePanelScreen(.main)
        #expect(suite.array(forKey: "commitShortcut") as? [Int] == [36, 1_048_576])
        #expect(suite.string(forKey: "panelScreen") == "main")
    }

    @Test("AC-14: suite の指定が無い・空なら、suite を作らず標準の保存先を使う")
    func settingsDefaultsUsesStandardWithoutSuite() {
        let environments: [[String: String]] = [
            [:],
            ["TATAKINOTE_SETTINGS_SUITE": ""],
            ["HOME": "/Users/test"],
        ]

        for environment in environments {
            var requestedNames: [String] = []
            let defaults = AppLaunchContext.settingsDefaults(environment: environment) { requested in
                requestedNames.append(requested)
                return nil
            }
            #expect(requestedNames.isEmpty, "\(environment)")
            #expect(defaults === UserDefaults.standard, "\(environment)")
        }
    }

    // MARK: - 下書きと履歴の保存先

    @Test("AC-6: 単体テストの実行中は、ほかの指定があっても保存先は無し(ファイルに触れない)")
    func dataDirectoryIsNilWhileRunningUnitTests() {
        let environments: [[String: String]] = [
            ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"],
            ["XCTestBundlePath": "/tmp/TatakiNoteTests.xctest"],
            [
                "XCTestBundlePath": "/tmp/TatakiNoteTests.xctest",
                "TATAKINOTE_DATA_DIRECTORY": "/tmp/data",
                "TATAKINOTE_SETTINGS_SUITE": "suite",
            ],
        ]
        for environment in environments {
            #expect(AppLaunchContext.dataDirectory(environment: environment, bundleIdentifier: "jp.co.woube.TatakiNote") == nil, "\(environment)")
        }
    }

    @Test("AC-6: DEBUG で TATAKINOTE_DATA_DIRECTORY があればその場所で、設定の suite の指定より優先する")
    func dataDirectoryFollowsEnvironmentVariable() {
        let environment = ["TATAKINOTE_DATA_DIRECTORY": "/tmp/tataki-data", "TATAKINOTE_SETTINGS_SUITE": "suite"]

        let url = AppLaunchContext.dataDirectory(environment: environment, bundleIdentifier: "jp.co.woube.TatakiNote")

        #expect(url?.path == "/tmp/tataki-data")
    }

    @Test("AC-6: DEBUG で設定の suite を指定した起動では、一時ディレクトリの下の suite 名のフォルダ")
    func dataDirectoryIsUnderTemporaryDirectoryForSettingsSuite() {
        let url = AppLaunchContext.dataDirectory(
            environment: ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc"],
            bundleIdentifier: "jp.co.woube.TatakiNote"
        )

        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("TatakiNote-TatakiNoteUITests.abc", isDirectory: true)
        #expect(url?.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test("AC-6: それ以外は Application Support のバンドル ID のフォルダ。バンドル ID が取れなければ TatakiNote")
    func dataDirectoryDefaultsToApplicationSupport() {
        let withBundle = AppLaunchContext.dataDirectory(environment: [:], bundleIdentifier: "jp.co.woube.TatakiNote")
        #expect(withBundle == URL.applicationSupportDirectory.appendingPathComponent("jp.co.woube.TatakiNote", isDirectory: true))

        let emptyValues: [[String: String]] = [
            [:],
            ["TATAKINOTE_DATA_DIRECTORY": ""],
            ["TATAKINOTE_SETTINGS_SUITE": ""],
            ["HOME": "/Users/test"],
        ]
        for environment in emptyValues {
            let url = AppLaunchContext.dataDirectory(environment: environment, bundleIdentifier: nil)
            #expect(url == URL.applicationSupportDirectory.appendingPathComponent("TatakiNote", isDirectory: true), "\(environment)")
            let emptyBundle = AppLaunchContext.dataDirectory(environment: environment, bundleIdentifier: "")
            #expect(emptyBundle == url, "\(environment)")
        }
    }

    // MARK: - 権限の状態の上書きと、起動時の案内

    @Test("AC-7: DEBUG で TATAKINOTE_ACCESSIBILITY_OVERRIDE が trusted / untrusted のときだけ上書きし、それ以外は本物の権限を使う")
    func accessibilityOverride() {
        #expect(AppLaunchContext.accessibilityOverride(environment: ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "trusted"]) == true)
        #expect(AppLaunchContext.accessibilityOverride(environment: ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "untrusted"]) == false)

        let trusted = AppLaunchContext.accessibilityPermission(environment: ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "trusted"])
        #expect((trusted as? OverriddenAccessibilityPermission)?.isTrusted == true)
        let untrusted = AppLaunchContext.accessibilityPermission(environment: ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "untrusted"])
        #expect((untrusted as? OverriddenAccessibilityPermission)?.isTrusted == false)
        #expect(untrusted.isTrusted == false)

        let withoutOverride: [[String: String]] = [
            [:],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": ""],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "yes"],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "Trusted"],
            ["tatakinote_accessibility_override": "trusted"],
            ["HOME": "/Users/test"],
        ]
        for environment in withoutOverride {
            #expect(AppLaunchContext.accessibilityOverride(environment: environment) == nil, "\(environment)")
            let permission = AppLaunchContext.accessibilityPermission(environment: environment)
            #expect(permission is SystemAccessibilityPermission, "\(environment)")
        }
    }

    @Test("AC-7: 上書きした権限は決めた値を返し、システムの許可のダイアログを出さない")
    func overriddenPermission() {
        #expect(OverriddenAccessibilityPermission(isTrusted: false).isTrusted == false)
        #expect(OverriddenAccessibilityPermission(isTrusted: true).isTrusted == true)
        OverriddenAccessibilityPermission(isTrusted: false).requestSystemPrompt()
    }

    @Test("AC-12: 単体テストのホストでは起動時に権限の案内を出さず、それ以外の起動では上書きの有無にかかわらず判定に進む")
    func permissionGuideOnLaunch() {
        let unitTestHosts: [[String: String]] = [
            ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"],
            ["XCTestBundlePath": "/tmp/TatakiNoteTests.xctest"],
            ["XCTestConfigurationFilePath": "/tmp/a", "XCTestBundlePath": "/tmp/b", "HOME": "/Users/test"],
            ["XCTestBundlePath": "/tmp/b", "TATAKINOTE_ACCESSIBILITY_OVERRIDE": "untrusted"],
        ]
        for environment in unitTestHosts {
            #expect(AppLaunchContext.shouldPresentPermissionGuideOnLaunch(environment: environment) == false, "\(environment)")
        }

        let otherLaunches: [[String: String]] = [
            [:],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "untrusted"],
            ["TATAKINOTE_ACCESSIBILITY_OVERRIDE": "trusted"],
            ["XCTestSessionIdentifier": "abc", "XCTestManagerVariant": "DDI"],
        ]
        for environment in otherLaunches {
            #expect(AppLaunchContext.shouldPresentPermissionGuideOnLaunch(environment: environment) == true, "\(environment)")
        }
    }

    // MARK: - ログイン項目の上書きと、開き直し

    @Test("AC-7: DEBUG で TATAKINOTE_LOGIN_ITEM_OVERRIDE が memory のときだけ OS に何もしないログイン項目を使い、それ以外は本物を使う")
    func loginItemOverride() {
        let overridden = AppLaunchContext.loginItemService(environment: ["TATAKINOTE_LOGIN_ITEM_OVERRIDE": "memory"])
        #expect(overridden is InMemoryLoginItemService)
        #expect(overridden.status == .notRegistered)
        #expect(
            AppLaunchContext.loginItemService(
                environment: ["TATAKINOTE_LOGIN_ITEM_OVERRIDE": "memory", "TATAKINOTE_ACCESSIBILITY_OVERRIDE": "untrusted"]
            ) is InMemoryLoginItemService
        )

        let withoutOverride: [[String: String]] = [
            [:],
            ["TATAKINOTE_LOGIN_ITEM_OVERRIDE": ""],
            ["TATAKINOTE_LOGIN_ITEM_OVERRIDE": "Memory"],
            ["TATAKINOTE_LOGIN_ITEM_OVERRIDE": "real"],
            ["tatakinote_login_item_override": "memory"],
            ["HOME": "/Users/test"],
        ]
        for environment in withoutOverride {
            let service = AppLaunchContext.loginItemService(environment: environment)
            #expect(service is MainAppLoginItemService, "\(environment)")
            #expect(!(service is InMemoryLoginItemService), "\(environment)")
        }
    }

    @Test("AC-12: DEBUG で TATAKINOTE_INSERTION_TARGET が none のときだけ挿入先を探さず、他の値・空・無しでは今までどおり")
    func insertionTargetDisabled() {
        #expect(AppLaunchContext.isInsertionTargetDisabled(environment: ["TATAKINOTE_INSERTION_TARGET": "none"]) == true)
        #expect(
            AppLaunchContext.isInsertionTargetDisabled(
                environment: ["TATAKINOTE_INSERTION_TARGET": "none", "HOME": "/Users/test"]
            ) == true
        )

        let enabled: [[String: String]] = [
            [:],
            ["TATAKINOTE_INSERTION_TARGET": ""],
            ["TATAKINOTE_INSERTION_TARGET": "None"],
            ["TATAKINOTE_INSERTION_TARGET": "frontmost"],
            ["tatakinote_insertion_target": "none"],
            ["HOME": "/Users/test"],
        ]
        for environment in enabled {
            #expect(AppLaunchContext.isInsertionTargetDisabled(environment: environment) == false, "\(environment)")
        }
    }

    // MARK: - アイコンから開く動きの抑止

    private static let suite = "TATAKINOTE_SETTINGS_SUITE"
    private static let launchKey = "TATAKINOTE_OPEN_PANEL_ON_LAUNCH"
    private static let reopenKey = "TATAKINOTE_OPEN_PANEL_ON_REOPEN"

    @Test("AC-9: suite を指定した起動は、enabled が無ければ起動の後にパネルを開かず、もう一方の環境変数だけ enabled でも開かない")
    func suiteLaunchSuppressesOpenPanelOnLaunch() {
        let environments: [[String: String]] = [
            [Self.suite: "TatakiNoteUITests.abc"],
            [Self.suite: "TatakiNoteUITests.abc", Self.launchKey: ""],
            [Self.suite: "TatakiNoteUITests.abc", Self.launchKey: "1"],
            [Self.suite: "TatakiNoteUITests.abc", Self.reopenKey: "enabled"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isOpenPanelOnLaunchSuppressed(environment: environment) == true, "\(environment)")
        }
    }

    @Test("AC-9: suite を指定して TATAKINOTE_OPEN_PANEL_ON_LAUNCH=enabled を付けた起動は、起動の後にパネルを開く")
    func suiteLaunchWithEnabledOpensPanelOnLaunch() {
        let environment = [Self.suite: "TatakiNoteUITests.abc", Self.launchKey: "enabled"]

        #expect(AppLaunchContext.isOpenPanelOnLaunchSuppressed(environment: environment) == false)
    }

    @Test("AC-9: suite を指定しない起動は、起動の後にパネルを開く動きを抑止しない")
    func launchWithoutSuiteDoesNotSuppressOpenPanelOnLaunch() {
        let environments: [[String: String]] = [
            [:],
            [Self.suite: ""],
            [Self.launchKey: "enabled"],
            [Self.launchKey: "other"],
            ["HOME": "/Users/test"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isOpenPanelOnLaunchSuppressed(environment: environment) == false, "\(environment)")
        }
    }

    @Test("AC-9: suite を指定した起動は、enabled が無ければもう一度開かれてもパネルを開かず、もう一方の環境変数だけ enabled でも開かない")
    func suiteLaunchSuppressesOpenPanelOnReopen() {
        let environments: [[String: String]] = [
            [Self.suite: "TatakiNoteUITests.abc"],
            [Self.suite: "TatakiNoteUITests.abc", Self.reopenKey: ""],
            [Self.suite: "TatakiNoteUITests.abc", Self.reopenKey: "1"],
            [Self.suite: "TatakiNoteUITests.abc", Self.launchKey: "enabled"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isOpenPanelOnReopenSuppressed(environment: environment) == true, "\(environment)")
        }
    }

    @Test("AC-9: suite を指定して TATAKINOTE_OPEN_PANEL_ON_REOPEN=enabled を付けた起動は、もう一度開かれたらパネルを開く")
    func suiteLaunchWithEnabledOpensPanelOnReopen() {
        let environment = [Self.suite: "TatakiNoteUITests.abc", Self.reopenKey: "enabled"]

        #expect(AppLaunchContext.isOpenPanelOnReopenSuppressed(environment: environment) == false)
    }

    @Test("AC-9: suite を指定しない起動は、もう一度開かれたときにパネルを開く動きを抑止しない")
    func launchWithoutSuiteDoesNotSuppressOpenPanelOnReopen() {
        let environments: [[String: String]] = [
            [:],
            [Self.suite: ""],
            [Self.reopenKey: "enabled"],
            [Self.reopenKey: "other"],
            ["HOME": "/Users/test"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isOpenPanelOnReopenSuppressed(environment: environment) == false, "\(environment)")
        }
    }

    // MARK: - 更新の仕組みの選び分け

    private static let updateOverride = "TATAKINOTE_UPDATE_OVERRIDE"
    private static let unitTestMark = "XCTestConfigurationFilePath"

    @Test("AC-21: 単体テストの起動は、ビルドの種類・環境変数に関係なく何もしない仕組みになる", arguments: [true, false])
    func updaterKindIsInertWhileRunningUnitTests(isDebugBuild: Bool) {
        let environments: [[String: String]] = [
            [Self.unitTestMark: "/tmp/config.xctestconfiguration"],
            [Self.unitTestMark: "/tmp/config.xctestconfiguration", Self.updateOverride: "available"],
        ]
        for environment in environments {
            #expect(
                AppLaunchContext.updaterKind(environment: environment, isDebugBuild: isDebugBuild) == .inert,
                "\(environment)"
            )
        }
    }

    @Test("AC-21: DEBUG のビルドは、TATAKINOTE_UPDATE_OVERRIDE=available のときだけ新しいバージョンありの偽物、それ以外は何もしない仕組み")
    func updaterKindInDebugBuild() {
        #expect(AppLaunchContext.updaterKind(environment: [:], isDebugBuild: true) == .inert)
        #expect(AppLaunchContext.updaterKind(environment: [Self.updateOverride: "available"], isDebugBuild: true) == .preview)
        #expect(AppLaunchContext.updaterKind(environment: [Self.updateOverride: "other"], isDebugBuild: true) == .inert)
        #expect(AppLaunchContext.updaterKind(environment: [Self.updateOverride: ""], isDebugBuild: true) == .inert)
    }

    @Test("AC-21: リリースのビルドは、環境変数に関係なく Sparkle になる")
    func updaterKindInReleaseBuild() {
        #expect(AppLaunchContext.updaterKind(environment: [:], isDebugBuild: false) == .sparkle)
        #expect(AppLaunchContext.updaterKind(environment: [Self.updateOverride: "available"], isDebugBuild: false) == .sparkle)
        #expect(AppLaunchContext.updaterKind(environment: [Self.updateOverride: "other"], isDebugBuild: false) == .sparkle)
    }

    // MARK: - 移動の確認の抑止

    private static let movePrompt = "TATAKINOTE_MOVE_PROMPT"

    @Test("AC-22: 単体テストの起動は、ビルドの種類・環境変数に関係なく移動を聞かない", arguments: [true, false])
    func moveToApplicationsIsNotOfferedWhileRunningUnitTests(isDebugBuild: Bool) {
        let environments: [[String: String]] = [
            [Self.unitTestMark: "/tmp/config.xctestconfiguration"],
            [Self.unitTestMark: "/tmp/config.xctestconfiguration", Self.movePrompt: "enabled"],
        ]
        for environment in environments {
            #expect(
                AppLaunchContext.shouldOfferMoveToApplications(environment: environment, isDebugBuild: isDebugBuild) == false,
                "\(environment)"
            )
        }
    }

    @Test("AC-22: DEBUG のビルドは、TATAKINOTE_MOVE_PROMPT=enabled のときだけ移動を聞く")
    func moveToApplicationsInDebugBuild() {
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [:], isDebugBuild: true) == false)
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [Self.movePrompt: "enabled"], isDebugBuild: true) == true)
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [Self.movePrompt: "other"], isDebugBuild: true) == false)
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [Self.movePrompt: ""], isDebugBuild: true) == false)
    }

    @Test("AC-22: リリースのビルドは、環境変数に関係なく移動を聞く")
    func moveToApplicationsInReleaseBuild() {
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [:], isDebugBuild: false) == true)
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [Self.movePrompt: "enabled"], isDebugBuild: false) == true)
        #expect(AppLaunchContext.shouldOfferMoveToApplications(environment: [Self.movePrompt: "other"], isDebugBuild: false) == true)
    }
}
