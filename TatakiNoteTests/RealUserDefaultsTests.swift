import Foundation
import Testing
@testable import TatakiNote

/// 本物の `UserDefaults` に保存して確かめる。suite の名前は固定。
@MainActor
@Suite(.serialized)
struct RealUserDefaultsTests {
    private static let suitePrefix = "TatakiNoteTests.RealUserDefaults"

    private func withSuite(_ caseName: String, _ body: (String, UserDefaults) throws -> Void) throws {
        let name = "\(Self.suitePrefix).\(caseName)"
        let suite = try #require(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        defer { suite.removePersistentDomain(forName: name) }
        try body(name, suite)
    }

    // MARK: - AppLaunchContext.settingsDefaults

    @Test("AC-14: suite の指定があれば、その名前の suite に保存し、標準の保存先は使わない")
    func settingsDefaultsUsesNamedSuite() throws {
        try withSuite("namedSuite") { name, suite in
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
    }

    @Test("AC-13: suite の指定と設定の値があれば、起動時に選ぶ suite にその値が書かれる")
    func settingsDefaultsAppliesSeedToSuite() throws {
        try withSuite("seededSuite") { name, suite in
            let defaults = AppLaunchContext.settingsDefaults(environment: [
                "TATAKINOTE_SETTINGS_SUITE": name,
                SettingsSeed.environmentKey: #"{"commitKey":"none","panelFontSize":18}"#,
            ]) { _ in suite }

            #expect(defaults === suite)
            #expect(suite.string(forKey: "commitKey") == "none")
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            #expect(settings.commitKey == nil)
            #expect(settings.panelFontSize == 18)
        }
    }

    // MARK: - SettingsStore

    @Test("本物の UserDefaults に保存した設定は、作り直した設定から同じ値で読める")
    func savedSettingsRoundTrip() throws {
        try withSuite("roundTrip") { _, suite in
            let settings = AppSettings(store: SettingsStore(defaults: suite))
            settings.commitKey = .commandReturn
            settings.panelScreen = .mouse
            settings.autoShowMode = .selectedApps
            settings.autoShowApps = [AutoShowApp(bundleIdentifier: "com.example.chatmate", name: "Chatmate")]
            settings.panelFontSize = 18
            settings.panelOpacity = 0.4
            settings.hiddenPanelStatusItems = [.close]
            settings.hidesMenuBarIcon = true
            settings.historyLimit = 50

            let reloaded = AppSettings(store: SettingsStore(defaults: suite))
            #expect(reloaded.commitKey == .commandReturn)
            #expect(reloaded.panelScreen == .mouse)
            #expect(reloaded.autoShowMode == .selectedApps)
            #expect(reloaded.autoShowApps == [AutoShowApp(bundleIdentifier: "com.example.chatmate", name: "Chatmate")])
            #expect(reloaded.panelFontSize == 18)
            #expect(reloaded.panelOpacity == 0.4)
            #expect(reloaded.hiddenPanelStatusItems == [.close])
            #expect(reloaded.hidesMenuBarIcon == true)
            #expect(reloaded.historyLimit == 50)
        }
    }

    @Test("本物の UserDefaults でも、数値のキーの真偽値と真偽値のキーの数値は読まずに既定値になる")
    func numbersAndBooleansAreNotMixed() throws {
        try withSuite("numbersAndBooleans") { _, suite in
            suite.set(true, forKey: SettingsStore.Key.panelFontSize)
            suite.set(1, forKey: SettingsStore.Key.hidesMenuBarIcon)

            let settings = AppSettings(store: SettingsStore(defaults: suite))
            #expect(settings.panelFontSize == PanelTextStyle.defaultFontSize)
            #expect(settings.hidesMenuBarIcon == false)
        }
    }

    @Test("本物の UserDefaults の古い形式のキー(文字列)から、確定+挿入キーを読み替える")
    func legacyActionKeyIsRead() throws {
        try withSuite("legacyActionKey") { _, suite in
            suite.set("shiftEnter", forKey: SettingsStore.Key.commitKey)

            let settings = AppSettings(store: SettingsStore(defaults: suite))
            #expect(settings.commitKey == .shiftReturn)
        }
    }
}
