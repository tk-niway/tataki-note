import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct FirstLaunchFlowTests {
    private func makeDefaults() throws -> (defaults: UserDefaults, cleanup: () -> Void) {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: - 保存

    @Test("AC-1: 表示済みは保存され、AppSettings を作り直しても残る。保存が無ければ未表示")
    func shownFlagPersistsAcrossRelaunch() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hasShownFirstLaunchTutorial == false)

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.hasShownFirstLaunchTutorial = true
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hasShownFirstLaunchTutorial == true)

        settings.hasShownFirstLaunchTutorial = false
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hasShownFirstLaunchTutorial == false)
    }

    @Test("AC-3: 表示済みのキーに Bool でない値があっても未表示として読み、ほかの設定は変わらない")
    func nonBooleanValueIsReadAsNotShown() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        let store = SettingsStore(defaults: defaults)
        store.savePanelScreen(.main)
        store.savePanelFontSize(20)
        store.saveHidesMenuBarIcon(true)

        let invalidValues: [Any] = ["true", "yes", "", 1, 0, 2.5]
        for value in invalidValues {
            defaults.set(value, forKey: SettingsStore.Key.hasShownFirstLaunchTutorial)
            #expect(store.loadHasShownFirstLaunchTutorial() == false, "\(value)")

            let settings = AppSettings(store: store)
            #expect(settings.hasShownFirstLaunchTutorial == false, "\(value)")
            #expect(settings.panelScreen == .main, "\(value)")
            #expect(settings.panelFontSize == 20, "\(value)")
            #expect(settings.hidesMenuBarIcon == true, "\(value)")
        }
    }

    // MARK: - 起動時に出すもの

    @Test("AC-2: 未表示+許可あり → チュートリアル、未表示+許可なし → 初回起動の案内、表示済み → 今までどおり")
    func presentationTable() {
        #expect(FirstLaunchFlow.presentation(hasShownTutorial: false, isTrusted: true) == .tutorial)
        #expect(FirstLaunchFlow.presentation(hasShownTutorial: false, isTrusted: false) == .permissionGuide(.firstLaunch))
        #expect(FirstLaunchFlow.presentation(hasShownTutorial: true, isTrusted: true) == .nothing)
        #expect(FirstLaunchFlow.presentation(hasShownTutorial: true, isTrusted: false) == .permissionGuide(.launch))
    }

    @Test("AC-2: 判定の後は表示済みになり、次の起動でチュートリアルは出ない(許可あり)")
    func resolveMarksShownWhenTrusted() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        let first = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: first, isTrusted: true, isSuppressed: false) == .tutorial)
        #expect(first.hasShownFirstLaunchTutorial == true)

        let second = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: second, isTrusted: true, isSuppressed: false) == .nothing)
    }

    @Test("AC-2: 判定の後は表示済みになり、次の起動は今までの許可の案内になる(許可なし)")
    func resolveMarksShownWhenNotTrusted() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        let first = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: first, isTrusted: false, isSuppressed: false) == .permissionGuide(.firstLaunch))
        #expect(first.hasShownFirstLaunchTutorial == true)

        let second = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: second, isTrusted: false, isSuppressed: false) == .permissionGuide(.launch))
    }

    @Test("AC-4: 抑止された起動は表示済みとして判定し、表示済みを保存しない")
    func suppressedLaunchBehavesAsShownAndDoesNotSave() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: settings, isTrusted: true, isSuppressed: true) == .nothing)
        #expect(FirstLaunchFlow.resolveOnLaunch(settings: settings, isTrusted: false, isSuppressed: true) == .permissionGuide(.launch))
        #expect(settings.hasShownFirstLaunchTutorial == false)
        #expect(defaults.object(forKey: SettingsStore.Key.hasShownFirstLaunchTutorial) == nil)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hasShownFirstLaunchTutorial == false)
    }

    // MARK: - 抑止の判定

    @Test("AC-4: DEBUG で suite を指定した起動は、TATAKINOTE_FIRST_LAUNCH_TUTORIAL=enabled が無ければ抑止する")
    func suiteLaunchIsSuppressedWithoutEnabled() {
        let environments: [[String: String]] = [
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc"],
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc", "TATAKINOTE_FIRST_LAUNCH_TUTORIAL": ""],
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc", "TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "Enabled"],
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc", "TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "disabled"],
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc", "TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "1"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isFirstLaunchTutorialSuppressed(environment: environment) == true, "\(environment)")
        }
    }

    @Test("AC-4: DEBUG で suite を指定し enabled を付けた起動は、初回起動の扱いになる(抑止しない)")
    func suiteLaunchWithEnabledIsNotSuppressed() {
        let environment = [
            "TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc",
            "TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "enabled",
        ]
        #expect(AppLaunchContext.isFirstLaunchTutorialSuppressed(environment: environment) == false)
    }

    @Test("AC-4: suite を指定しない起動は、環境変数にかかわらず抑止しない")
    func launchWithoutSuiteIsNotSuppressed() {
        let environments: [[String: String]] = [
            [:],
            ["TATAKINOTE_SETTINGS_SUITE": ""],
            ["TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "enabled"],
            ["TATAKINOTE_FIRST_LAUNCH_TUTORIAL": "other"],
            ["HOME": "/Users/test"],
        ]
        for environment in environments {
            #expect(AppLaunchContext.isFirstLaunchTutorialSuppressed(environment: environment) == false, "\(environment)")
        }
    }
}
