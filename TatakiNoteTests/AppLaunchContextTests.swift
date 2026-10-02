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
        let suite = try #require(UserDefaults(suiteName: name))
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

    @Test("AC-10: アイコンを隠しているときだけ、もう一度開かれたら設定画面を開く(出しているときは何もしない)")
    func settingsOnReopen() {
        #expect(AppLaunchContext.shouldOpenSettingsOnReopen(hidesMenuBarIcon: true) == true)
        #expect(AppLaunchContext.shouldOpenSettingsOnReopen(hidesMenuBarIcon: false) == false)
    }
}
