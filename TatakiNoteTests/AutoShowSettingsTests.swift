import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AutoShowSettingsTests {
    private let chrome = AutoShowApp(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    private let slack = AutoShowApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")
    private let vscode = AutoShowApp(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code")

    /// @note p0-790
    private func makeSuite() throws -> (UserDefaults, String) {
        let name = UUID().uuidString
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func removeSuite(_ defaults: UserDefaults, name: String) {
        defaults.removePersistentDomain(forName: name)
    }

    @Test("AC-1: 何も保存されていなければ、自動表示は「オフ」、選んだアプリの一覧は空")
    func defaultsWhenNothingSaved() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.loadAutoShowMode() == .off)
        #expect(store.loadAutoShowApps().isEmpty)

        // @note p0-791
        let settings = AppSettings(store: store)
        #expect(settings.autoShowMode == .off)
        #expect(settings.autoShowApps.isEmpty)
        #expect(defaults.object(forKey: "autoShowMode") == nil)
        #expect(defaults.object(forKey: "autoShowApps") == nil)
    }

    @Test("AC-2: 保存した自動表示の設定と選んだアプリの一覧は、別の SettingsStore で読み込んでも同じ値")
    func savedValuesAreLoadedAgain() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        for mode in AutoShowMode.allCases {
            SettingsStore(defaults: defaults).saveAutoShowMode(mode)
            #expect(SettingsStore(defaults: defaults).loadAutoShowMode() == mode, "\(mode)")
        }

        let appLists: [[AutoShowApp]] = [[chrome, slack, vscode], [vscode, chrome], [slack], []]
        for apps in appLists {
            SettingsStore(defaults: defaults).saveAutoShowApps(apps)
            #expect(SettingsStore(defaults: defaults).loadAutoShowApps() == apps, "\(apps)")
        }
    }

    @Test("AC-3: 知らない文字列・型の違う値・壊れた JSON が保存されていれば、自動表示は「オフ」、一覧は空")
    func unknownValuesFallBackToDefaults() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        // @note p0-792
        defaults.set("commandEnter", forKey: "commitKey")
        defaults.set("targetWindow", forKey: "panelScreen")

        let values: [Any] = [
            "unknown", "", "Off", "allapps", 1, 3.5, true,
            ["off"], ["off": "allApps"],
            // @note p0-793
            [["bundleIdentifier": "com.google.Chrome", "name": "Google Chrome"]],
            Data([0x01]),
            // @note p0-794
            Data("{".utf8),
            Data("[".utf8),
            Data("null".utf8),
            Data(#""allApps""#.utf8),
            Data(#"{"bundleIdentifier":"com.google.Chrome","name":"Google Chrome"}"#.utf8),
            Data(#"[{"bundleIdentifier":"com.google.Chrome"}]"#.utf8),
            Data(#"[{"bundleIdentifier":1,"name":"Google Chrome"}]"#.utf8),
        ]
        for value in values {
            defaults.set(value, forKey: "autoShowMode")
            defaults.set(value, forKey: "autoShowApps")
            #expect(store.loadAutoShowMode() == .off, "\(value)")
            #expect(store.loadAutoShowApps().isEmpty, "\(value)")

            let settings = AppSettings(store: store)
            #expect(settings.autoShowMode == .off, "\(value)")
            #expect(settings.autoShowApps.isEmpty, "\(value)")
            #expect(settings.panelScreen == .targetWindow, "\(value)")
        }
        #expect(defaults.string(forKey: "commitKey") == "commandEnter")
        #expect(defaults.string(forKey: "panelScreen") == "targetWindow")

        // @note p0-795
        store.saveAutoShowMode(.allApps)
        defaults.set(Data("{".utf8), forKey: "autoShowApps")
        #expect(store.loadAutoShowMode() == .allApps)
        #expect(store.loadAutoShowApps().isEmpty)

        store.saveAutoShowApps([chrome])
        defaults.set("unknown", forKey: "autoShowMode")
        #expect(store.loadAutoShowMode() == .off)
        #expect(store.loadAutoShowApps() == [chrome])
    }

    @Test("AC-4: 保存のキーは autoShowMode・autoShowApps で、値は決めた文字列と bundleIdentifier・name の JSON")
    func storageFormatIsFixed() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let modes: [(AutoShowMode, String)] = [
            (.off, "off"),
            (.allApps, "allApps"),
            (.selectedApps, "selectedApps"),
        ]
        for (mode, expected) in modes {
            store.saveAutoShowMode(mode)
            #expect(defaults.string(forKey: "autoShowMode") == expected)
        }

        store.saveAutoShowApps([chrome, slack])
        let data = try #require(defaults.data(forKey: "autoShowApps"))
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [[String: String]])
        #expect(json == [
            ["bundleIdentifier": "com.google.Chrome", "name": "Google Chrome"],
            ["bundleIdentifier": "com.tinyspeck.slackmacgap", "name": "Slack"],
        ])

        // @note p0-796
        for (mode, raw) in modes {
            defaults.set(raw, forKey: "autoShowMode")
            #expect(store.loadAutoShowMode() == mode)
        }
        defaults.set(
            Data(#"[{"bundleIdentifier":"com.microsoft.VSCode","name":"Visual Studio Code"},{"name":"Slack","bundleIdentifier":"com.tinyspeck.slackmacgap"}]"#.utf8),
            forKey: "autoShowApps"
        )
        #expect(store.loadAutoShowApps() == [vscode, slack])
    }

    @Test("AC-5: AppSettings の自動表示の設定を変えると保存され、作り直しても同じ値。確定キー・パネルを出す画面のキーには書き込まない")
    func appSettingsSavesAutoShowSettings() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chrome, slack]

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.autoShowMode == .selectedApps)
        #expect(reloaded.autoShowApps == [chrome, slack])

        // @note p0-797
        reloaded.autoShowMode = .allApps
        reloaded.autoShowApps = [vscode]
        let reloadedAgain = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloadedAgain.autoShowMode == .allApps)
        #expect(reloadedAgain.autoShowApps == [vscode])

        // @note p0-798
        reloadedAgain.autoShowMode = .off
        let turnedOff = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(turnedOff.autoShowMode == .off)
        #expect(turnedOff.autoShowApps == [vscode])
        turnedOff.autoShowApps = []
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).autoShowApps.isEmpty)

        #expect(defaults.object(forKey: "commitKey") == nil)
        #expect(defaults.object(forKey: "panelScreen") == nil)
    }

    @Test("AC-6: 同じ bundleIdentifier は先に入れた1件だけ、空の bundleIdentifier は入らず、並びは足した順")
    func appListIsNormalized() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let apps = [
            chrome,
            slack,
            AutoShowApp(bundleIdentifier: "com.google.Chrome", name: "Chrome(別名)"),
            AutoShowApp(bundleIdentifier: "", name: "名前だけ"),
            vscode,
        ]
        let expected = [chrome, slack, vscode]

        #expect(AutoShowApp.normalized(apps) == expected)

        // @note p0-799
        store.saveAutoShowApps(apps)
        #expect(SettingsStore(defaults: defaults).loadAutoShowApps() == expected)

        // @note p0-800
        defaults.set(try JSONEncoder().encode(apps), forKey: "autoShowApps")
        #expect(SettingsStore(defaults: defaults).loadAutoShowApps() == expected)

        // @note p0-801
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowApps = apps
        #expect(settings.autoShowApps == expected)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).autoShowApps == expected)

        // @note p0-802
        settings.autoShowApps.append(AutoShowApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack(別名)"))
        #expect(settings.autoShowApps == expected)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).autoShowApps == expected)
    }

    @Test("AC-7: contains は同じ bundleIdentifier があれば true、無い・nil・一覧が空なら false")
    func containsMatchesBundleIdentifier() {
        let apps = [chrome, slack]

        #expect(AutoShowApp.contains(apps, bundleIdentifier: "com.google.Chrome"))
        #expect(!AutoShowApp.contains(apps, bundleIdentifier: "com.microsoft.VSCode"))
        #expect(!AutoShowApp.contains(apps, bundleIdentifier: nil))
        #expect(!AutoShowApp.contains([], bundleIdentifier: "com.google.Chrome"))
    }
}
