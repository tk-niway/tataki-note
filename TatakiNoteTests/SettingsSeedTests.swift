import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsSeedTests {
    private func environment(seed: String) -> [String: String] {
        [SettingsSeed.environmentKey: seed]
    }

    private func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    // MARK: - values

    @Test("AC-13: 環境変数が無い・空なら、書く値は無い")
    func noSeedMeansNoValues() throws {
        let environments: [[String: String]] = [
            [:],
            [SettingsSeed.environmentKey: ""],
            ["TATAKINOTE_SETTINGS_SUITE": "TatakiNoteUITests.abc"],
            ["tatakinote_settings_seed": "{\"commitKey\":\"shiftEnter\"}"],
        ]
        for environment in environments {
            #expect(try SettingsSeed.values(environment: environment).isEmpty, "\(environment)")
        }
    }

    @Test("AC-13: JSON のオブジェクトを読むと、文字列・数値・真偽値・文字列の配列の型を保つ")
    func valuesKeepTypes() throws {
        let values = try SettingsSeed.values(environment: environment(
            seed: #"{"commitKey":"shiftEnter","panelOpacity":0.4,"panelFontSize":20,"hidesMenuBarIcon":true,"hiddenPanelStatusItems":["characterCount"]}"#
        ))

        #expect(values.count == 5)
        #expect(values["commitKey"] as? String == "shiftEnter")

        let opacity = try #require(values["panelOpacity"] as? NSNumber)
        #expect(!isBoolean(opacity))
        #expect(opacity.doubleValue == 0.4)

        let fontSize = try #require(values["panelFontSize"] as? NSNumber)
        #expect(!isBoolean(fontSize))
        #expect(fontSize.doubleValue == 20)

        #expect(isBoolean(values["hidesMenuBarIcon"]))
        #expect((values["hidesMenuBarIcon"] as? NSNumber)?.boolValue == true)

        #expect(values["hiddenPanelStatusItems"] as? [String] == ["characterCount"])
    }

    @Test("AC-13: JSON のオブジェクトでない(配列・文字列・壊れた JSON)ときは、黙って無視せずエラーにする")
    func nonObjectIsAnError() {
        let seeds = ["[1]", "\"x\"", "{", "1", "true", "null", "not json"]
        for seed in seeds {
            #expect(throws: SettingsSeed.SeedError.notJSONObject, "\(seed)") {
                try SettingsSeed.values(environment: environment(seed: seed))
            }
        }
    }

    @Test("AC-13: 使えない型の値(null・入れ子のオブジェクト・null や入れ子を含む配列)があるときは、そのキーを添えてエラーにする")
    func unsupportedValueIsAnError() {
        let seeds = [
            #"{"a":null}"#,
            #"{"a":{"b":1}}"#,
            #"{"a":[null]}"#,
            #"{"a":[["x"]]}"#,
            #"{"a":[{"b":1}]}"#,
            #"{"commitKey":"shiftEnter","a":null}"#,
        ]
        for seed in seeds {
            #expect(throws: SettingsSeed.SeedError.unsupportedValue(key: "a"), "\(seed)") {
                try SettingsSeed.values(environment: environment(seed: seed))
            }
        }
    }

    @Test("AC-13: 文字列と数値が混ざった配列・空の配列・空のオブジェクトは使える")
    func mixedAndEmptyValuesAreAccepted() throws {
        let values = try SettingsSeed.values(environment: environment(seed: #"{"a":["x",1,false],"b":[]}"#))
        #expect(values.count == 2)
        #expect((values["a"] as? [Any])?.count == 3)
        #expect((values["b"] as? [Any])?.isEmpty == true)

        #expect(try SettingsSeed.values(environment: environment(seed: "{}")).isEmpty)
    }

    // MARK: - apply

    @Test("AC-13: 書いた値は、その suite の設定として読まれる")
    func appliedValuesAreReadAsSettings() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        try SettingsSeed.apply(
            environment: environment(
                seed: #"{"commitKey":"shiftEnter","commitAndSendKey":"commandShiftEnter","panelOpacity":0.4,"hiddenPanelStatusItems":["characterCount"],"appTheme":"dark","hidesMenuBarIcon":true}"#
            ),
            to: defaults
        )

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.commitKey == .shiftReturn)
        #expect(settings.commitAndSendKey == .commandShiftReturn)
        #expect(settings.panelOpacity == 0.4)
        #expect(settings.hiddenPanelStatusItems == [.characterCount])
        #expect(settings.theme == .dark)
        #expect(settings.hidesMenuBarIcon == true)
    }

    @Test("AC-13: 環境変数が無ければ、suite に何も書かない")
    func applyWithoutSeedWritesNothing() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        try SettingsSeed.apply(environment: [:], to: defaults)
        #expect(defaults.persistentDomain(forName: name)?.isEmpty ?? true)
    }

    @Test("AC-13: 使えない型の値が1つでもあれば、ほかのキーも suite に書かずにエラーにする")
    func applyWithInvalidSeedWritesNothing() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(throws: SettingsSeed.SeedError.unsupportedValue(key: "a")) {
            try SettingsSeed.apply(environment: environment(seed: #"{"a":null,"commitKey":"shiftEnter"}"#), to: defaults)
        }
        #expect(defaults.object(forKey: "commitKey") == nil)
    }

    // MARK: - AppLaunchContext.settingsDefaults

    @Test("AC-13: suite の指定と設定の値があれば、起動時に選ぶ suite にその値が書かれる")
    func settingsDefaultsAppliesSeedToSuite() throws {
        let name = UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

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

    @Test("AC-13: suite の指定が無ければ、設定の値があっても suite を作らず標準の保存先を返し、何も書かない")
    func settingsDefaultsDoesNotSeedStandard() {
        var requestedNames: [String] = []
        let defaults = AppLaunchContext.settingsDefaults(environment: [SettingsSeed.environmentKey: "{"]) { requested in
            requestedNames.append(requested)
            return nil
        }

        #expect(requestedNames.isEmpty)
        #expect(defaults === UserDefaults.standard)
    }
}
