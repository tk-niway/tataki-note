import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingDefinitionsTests {
    private func withStore(_ body: (SettingsStore, InMemoryDefaults) throws -> Void) throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        try body(SettingsStore(defaults: temp.defaults), temp.defaults)
    }

    private func isBoolean(_ object: Any?) -> Bool {
        guard let number = object as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    // MARK: - AC-1 保存のキー

    @Test("AC-1: 定義の表の保存のキーは今のキーと同じ文字列で、重ならない")
    func keysMatchCurrentKeys() {
        let keys = [
            SettingDefinitions.commitKey.key,
            SettingDefinitions.commitAndSendKey.key,
            SettingDefinitions.panelScreen.key,
            SettingDefinitions.autoShowMode.key,
            SettingDefinitions.autoShowApps.key,
            SettingDefinitions.theme.key,
            SettingDefinitions.panelFontName.key,
            SettingDefinitions.panelFontFamilyName.key,
            SettingDefinitions.panelFontSize.key,
            SettingDefinitions.panelOpacity.key,
            SettingDefinitions.hiddenPanelStatusItems.key,
            SettingDefinitions.isMenuBarIconShown.key,
            SettingDefinitions.panelDefaultWidth.key,
            SettingDefinitions.panelDefaultHeight.key,
            SettingDefinitions.animationMode.key,
            SettingDefinitions.isInsertionTargetOutlineShown.key,
            SettingDefinitions.showsDockIcon.key,
            SettingDefinitions.confirmsQuit.key,
            SettingDefinitions.historyLimit.key,
            SettingDefinitions.historyRetention.key,
            SettingDefinitions.newDraftMode.key,
            SettingDefinitions.checksForUpdatesAutomatically.key,
            SettingDefinitions.hasShownFirstLaunchTutorial.key,
            SettingDefinitions.isSidebarOpen.key,
            SettingDefinitions.sidebarTab.key,
            SettingDefinitions.lastExportDirectoryPath.key,
            SettingDefinitions.lastUpdateCheckDate.key,
            SettingDefinitions.suppressesMoveToApplicationsPrompt.key,
        ]
        let expected = [
            "commitShortcut",
            "commitAndSendShortcut",
            "panelScreen",
            "autoShowMode",
            "autoShowApps",
            "appTheme",
            "panelFontName",
            "panelFontFamilyName",
            "panelFontSize",
            "panelOpacity",
            "hiddenPanelStatusItems",
            "hidesMenuBarIcon",
            "panelDefaultWidth",
            "panelDefaultHeight",
            "animationMode",
            "insertionTargetOutlineShown",
            "showsDockIcon",
            "confirmsQuit",
            "historyLimit",
            "historyRetention",
            "newDraftMode",
            "checksForUpdatesAutomatically",
            "hasShownFirstLaunchTutorial",
            "sidebarIsOpen",
            "sidebarTab",
            "lastExportDirectory",
            "lastUpdateCheckDate",
            "suppressesMoveToApplicationsPrompt",
        ]
        #expect(keys == expected)
        #expect(Set(keys).count == keys.count)
    }

    @Test("AC-1: 確定キーの旧形式のキー commitKey・commitAndSendKey から読み替える")
    func legacyCommitKeysAreRead() throws {
        try withStore { store, defaults in
            defaults.set("shiftEnter", forKey: "commitKey")
            defaults.set("commandShiftEnter", forKey: "commitAndSendKey")
            #expect(store.value(SettingDefinitions.commitKey) == .shiftReturn)
            #expect(store.value(SettingDefinitions.commitAndSendKey) == .commandShiftReturn)
        }
    }

    // MARK: - AC-4 読めない値

    @Test("AC-4: 真偽値の定義は真偽値だけを読み、数・文字列・無い値は初期値になる")
    func booleanReadsOnlyBooleans() throws {
        try withStore { store, defaults in
            let definition = SettingDefinitions.showsDockIcon
            #expect(store.value(definition) == true)
            defaults.set(false, forKey: "showsDockIcon")
            #expect(store.value(definition) == false)
            for unreadable: Any in [1, 0, "YES", "true", "false"] {
                defaults.set(unreadable, forKey: "showsDockIcon")
                #expect(store.value(definition) == true)
            }
            let falseByDefault = SettingDefinitions.isSidebarOpen
            defaults.set(1, forKey: "sidebarIsOpen")
            #expect(store.value(falseByDefault) == false)
        }
    }

    @Test("AC-4: メニューバーのアイコンは保存と逆の値で読み、真偽値でない値は表示する")
    func invertedBooleanReadsOpposite() throws {
        try withStore { store, defaults in
            let definition = SettingDefinitions.isMenuBarIconShown
            #expect(store.value(definition) == true)
            defaults.set(true, forKey: "hidesMenuBarIcon")
            #expect(store.value(definition) == false)
            defaults.set(false, forKey: "hidesMenuBarIcon")
            #expect(store.value(definition) == true)
            for unreadable: Any in [1, "YES"] {
                defaults.set(unreadable, forKey: "hidesMenuBarIcon")
                #expect(store.value(definition) == true)
            }
        }
    }

    @Test("AC-4: 列挙の定義は rawValue の文字列だけを読み、知らない値・数は初期値になる")
    func stringEnumFallsBackToDefault() throws {
        try withStore { store, defaults in
            let definition = SettingDefinitions.panelScreen
            #expect(store.value(definition) == .nearFocusedField)
            defaults.set("main", forKey: "panelScreen")
            #expect(store.value(definition) == .main)
            for unreadable: Any in [1, "", "Both", "Main"] {
                defaults.set(unreadable, forKey: "panelScreen")
                #expect(store.value(definition) == .nearFocusedField)
            }
            defaults.set("history", forKey: "sidebarTab")
            #expect(store.value(SettingDefinitions.sidebarTab) == .history)
            defaults.set("nothing", forKey: "newDraftMode")
            #expect(store.value(SettingDefinitions.newDraftMode) == .insert)
        }
    }

    @Test("AC-4: 空でない文字列だけを読み、無い・空・文字列でない値は nil")
    func nonEmptyStringReadsOnlyNonEmpty() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.panelFontName) == nil)
            defaults.set("Menlo", forKey: "panelFontName")
            #expect(store.value(SettingDefinitions.panelFontName) == "Menlo")
            for unreadable: Any in ["", 12, true] {
                defaults.set(unreadable, forKey: "panelFontName")
                #expect(store.value(SettingDefinitions.panelFontName) == nil)
                defaults.set(unreadable, forKey: "lastExportDirectory")
                #expect(store.value(SettingDefinitions.lastExportDirectoryPath) == nil)
            }
            defaults.set("/tmp/export", forKey: "lastExportDirectory")
            #expect(store.value(SettingDefinitions.lastExportDirectoryPath) == "/tmp/export")
        }
    }

    @Test("AC-4: 文字サイズ・透明度は範囲の端に丸めて読み、真偽値・文字列・有限でない数は初期値")
    func clampedNumberClampsAndFallsBack() throws {
        try withStore { store, defaults in
            defaults.set(5.0, forKey: "panelFontSize")
            #expect(store.value(SettingDefinitions.panelFontSize) == 10)
            defaults.set(99, forKey: "panelFontSize")
            #expect(store.value(SettingDefinitions.panelFontSize) == 32)
            defaults.set(20.0, forKey: "panelFontSize")
            #expect(store.value(SettingDefinitions.panelFontSize) == 20)
            for unreadable: Any in [true, "14", Double.nan, Double.infinity] {
                defaults.set(unreadable, forKey: "panelFontSize")
                #expect(store.value(SettingDefinitions.panelFontSize) == 14)
            }
            #expect(store.value(SettingDefinitions.panelOpacity) == 1.0)
            defaults.set(0.1, forKey: "panelOpacity")
            #expect(store.value(SettingDefinitions.panelOpacity) == 0.4)
            defaults.set(7.0, forKey: "panelOpacity")
            #expect(store.value(SettingDefinitions.panelOpacity) == 1.0)
            defaults.set("0.5", forKey: "panelOpacity")
            #expect(store.value(SettingDefinitions.panelOpacity) == 1.0)
        }
    }

    @Test("AC-4: 既定の幅・高さは範囲外・有限でない数を丸めず初期値として読む")
    func numberInRangeFallsBackWithoutClamping() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.panelDefaultWidth) == 520)
            #expect(store.value(SettingDefinitions.panelDefaultHeight) == 340)
            defaults.set(800.0, forKey: "panelDefaultWidth")
            defaults.set(600.0, forKey: "panelDefaultHeight")
            #expect(store.value(SettingDefinitions.panelDefaultWidth) == 800)
            #expect(store.value(SettingDefinitions.panelDefaultHeight) == 600)
            for unreadable: Any in [10.0, 99_999.0, Double.nan, Double.infinity, true, "800"] {
                defaults.set(unreadable, forKey: "panelDefaultWidth")
                #expect(store.value(SettingDefinitions.panelDefaultWidth) == 520)
                defaults.set(unreadable, forKey: "panelDefaultHeight")
                #expect(store.value(SettingDefinitions.panelDefaultHeight) == 340)
            }
        }
    }

    @Test("AC-4: 履歴の件数は有限な数を Double のまま丸めて Int にし、それ以外は初期値")
    func historyLimitClampsAndFallsBack() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.historyLimit) == 200)
            let cases: [(Any, Int)] = [
                (5000.0, 1000),
                (3.7, 10),
                (50, 50),
                (-3, 10),
                (Double.infinity, 200),
                (Double.nan, 200),
                (true, 200),
                ("50", 200),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "historyLimit")
                #expect(store.value(SettingDefinitions.historyLimit) == expected)
            }
        }
    }

    @Test("AC-4: 前回の確認日時は有限な数だけを日時として読み、それ以外は nil")
    func lastUpdateCheckDateReadsFiniteNumbers() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.lastUpdateCheckDate) == nil)
            defaults.set(1_800_000_000.0, forKey: "lastUpdateCheckDate")
            #expect(store.value(SettingDefinitions.lastUpdateCheckDate) == Date(timeIntervalSince1970: 1_800_000_000))
            for unreadable: Any in [true, "1800000000", Double.nan, Double.infinity] {
                defaults.set(unreadable, forKey: "lastUpdateCheckDate")
                #expect(store.value(SettingDefinitions.lastUpdateCheckDate) == nil)
            }
        }
    }

    @Test("AC-4: 確定キーは新形式・旧形式・登録なしを読み、読めない値や旧形式があるときの初期値を使い分ける")
    func commitKeysReadAllForms() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.commitKey) == .commandShiftReturn)
            #expect(store.value(SettingDefinitions.commitAndSendKey) == .commandReturn)

            defaults.set(PanelShortcut.shiftReturn.storedValue, forKey: "commitShortcut")
            #expect(store.value(SettingDefinitions.commitKey) == .shiftReturn)
            defaults.set([Int](), forKey: "commitShortcut")
            #expect(store.value(SettingDefinitions.commitKey) == nil)
            defaults.set("garbage", forKey: "commitShortcut")
            #expect(store.value(SettingDefinitions.commitKey) == .commandShiftReturn)
            defaults.set(["a"], forKey: "commitShortcut")
            #expect(store.value(SettingDefinitions.commitKey) == .commandShiftReturn)
        }
        try withStore { store, defaults in
            defaults.set("commandEnter", forKey: "commitAndSendKey")
            #expect(store.value(SettingDefinitions.commitAndSendKey) == .commandReturn)
            #expect(store.value(SettingDefinitions.commitKey) == .commandReturn)
        }
        try withStore { store, defaults in
            defaults.set("unknown", forKey: "commitKey")
            #expect(store.value(SettingDefinitions.commitKey) == .commandReturn)
            #expect(store.value(SettingDefinitions.commitAndSendKey) == nil)
        }
        try withStore { store, defaults in
            defaults.set("none", forKey: "commitKey")
            #expect(store.value(SettingDefinitions.commitKey) == nil)
        }
    }

    @Test("AC-4: 帯の非表示の項目は知っている rawValue だけを読み、自動表示のアプリは読めなければ空")
    func collectionsReadOnlyKnownValues() throws {
        try withStore { store, defaults in
            #expect(store.value(SettingDefinitions.hiddenPanelStatusItems).isEmpty)
            defaults.set(["lineCount", "unknown", 3, "close"], forKey: "hiddenPanelStatusItems")
            #expect(store.value(SettingDefinitions.hiddenPanelStatusItems) == [.lineCount, .close])

            #expect(store.value(SettingDefinitions.autoShowApps).isEmpty)
            defaults.set(Data("not json".utf8), forKey: "autoShowApps")
            #expect(store.value(SettingDefinitions.autoShowApps).isEmpty)
            defaults.set("text", forKey: "autoShowApps")
            #expect(store.value(SettingDefinitions.autoShowApps).isEmpty)
        }
    }

    // MARK: - AC-6 保存の形

    @Test("AC-6: 真偽値は真偽値で保存し、メニューバーのアイコンは逆の値で保存する")
    func booleansAreStoredAsBooleans() throws {
        try withStore { store, defaults in
            store.set(false, for: SettingDefinitions.showsDockIcon)
            #expect(isBoolean(defaults.object(forKey: "showsDockIcon")))
            #expect(defaults.object(forKey: "showsDockIcon") as? Bool == false)

            store.set(false, for: SettingDefinitions.isMenuBarIconShown)
            #expect(isBoolean(defaults.object(forKey: "hidesMenuBarIcon")))
            #expect(defaults.object(forKey: "hidesMenuBarIcon") as? Bool == true)
            store.set(true, for: SettingDefinitions.isMenuBarIconShown)
            #expect(defaults.object(forKey: "hidesMenuBarIcon") as? Bool == false)
        }
    }

    @Test("AC-6: 数は数で、列挙は rawValue の文字列で保存する")
    func numbersAndEnumsAreStoredInTheirForms() throws {
        try withStore { store, defaults in
            store.set(20.0, for: SettingDefinitions.panelFontSize)
            #expect(defaults.object(forKey: "panelFontSize") as? Double == 20)
            #expect(!isBoolean(defaults.object(forKey: "panelFontSize")))
            store.set(50, for: SettingDefinitions.historyLimit)
            #expect(defaults.object(forKey: "historyLimit") as? Int == 50)
            store.set(.main, for: SettingDefinitions.panelScreen)
            #expect(defaults.object(forKey: "panelScreen") as? String == "main")
            store.set(.history, for: SettingDefinitions.sidebarTab)
            #expect(defaults.object(forKey: "sidebarTab") as? String == "history")
        }
    }

    @Test("AC-6: 確定キーは数の配列で保存し、登録なしは空の配列。旧形式のキーには書かない")
    func commitKeysAreStoredAsIntegerArrays() throws {
        try withStore { store, defaults in
            defaults.set("shiftEnter", forKey: "commitKey")
            store.set(.shiftReturn, for: SettingDefinitions.commitKey)
            #expect(defaults.array(forKey: "commitShortcut") as? [Int] == PanelShortcut.shiftReturn.storedValue)
            store.set(nil, for: SettingDefinitions.commitAndSendKey)
            #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == [])
            #expect(defaults.object(forKey: "commitKey") as? String == "shiftEnter")
            #expect(defaults.object(forKey: "commitAndSendKey") == nil)
            #expect(store.value(SettingDefinitions.commitAndSendKey) == nil)
        }
    }

    @Test("AC-6: 帯の非表示の項目は allCases の順の配列で、自動表示のアプリは JSON の Data で保存する")
    func collectionsAreStoredInTheirForms() throws {
        try withStore { store, defaults in
            store.set([.lineCount, .close, .commit], for: SettingDefinitions.hiddenPanelStatusItems)
            let expectedOrder = PanelStatusItem.allCases.filter { [.lineCount, .close, .commit].contains($0) }.map(\.rawValue)
            #expect(defaults.array(forKey: "hiddenPanelStatusItems") as? [String] == expectedOrder)

            let apps = [AutoShowApp(bundleIdentifier: "com.example.a", name: "A")]
            store.set(apps, for: SettingDefinitions.autoShowApps)
            let data = try #require(defaults.data(forKey: "autoShowApps"))
            #expect(try JSONDecoder().decode([AutoShowApp].self, from: data) == apps)
            #expect(store.value(SettingDefinitions.autoShowApps) == apps)
        }
    }

    @Test("AC-6: 日付は 1970 年からの秒で保存し、nil と有限でない日付はキーを消す")
    func dateIsStoredAsSecondsAndNilRemovesKey() throws {
        try withStore { store, defaults in
            store.set(Date(timeIntervalSince1970: 1_800_000_000), for: SettingDefinitions.lastUpdateCheckDate)
            #expect(defaults.object(forKey: "lastUpdateCheckDate") as? Double == 1_800_000_000)
            store.set(nil, for: SettingDefinitions.lastUpdateCheckDate)
            #expect(defaults.object(forKey: "lastUpdateCheckDate") == nil)

            store.set(Date(timeIntervalSince1970: 1), for: SettingDefinitions.lastUpdateCheckDate)
            store.set(Date(timeIntervalSince1970: .nan), for: SettingDefinitions.lastUpdateCheckDate)
            #expect(defaults.object(forKey: "lastUpdateCheckDate") == nil)
        }
    }

    @Test("AC-6: nil・空文字のフォント名と書き出し先はキーを消す")
    func nilOrEmptyStringsRemoveKeys() throws {
        try withStore { store, defaults in
            store.set("Menlo", for: SettingDefinitions.panelFontName)
            #expect(defaults.object(forKey: "panelFontName") as? String == "Menlo")
            store.set("", for: SettingDefinitions.panelFontName)
            #expect(defaults.object(forKey: "panelFontName") == nil)
            store.set("Menlo", for: SettingDefinitions.panelFontFamilyName)
            store.set(nil, for: SettingDefinitions.panelFontFamilyName)
            #expect(defaults.object(forKey: "panelFontFamilyName") == nil)

            store.set("/tmp/export", for: SettingDefinitions.lastExportDirectoryPath)
            #expect(defaults.object(forKey: "lastExportDirectory") as? String == "/tmp/export")
            store.set("", for: SettingDefinitions.lastExportDirectoryPath)
            #expect(defaults.object(forKey: "lastExportDirectory") == nil)
            store.set("/tmp/export", for: SettingDefinitions.lastExportDirectoryPath)
            store.set(nil, for: SettingDefinitions.lastExportDirectoryPath)
            #expect(defaults.object(forKey: "lastExportDirectory") == nil)
        }
    }

    @Test("AC-6: set に範囲外の値を渡しても、範囲に収めて保存する")
    func setClampsOutOfRangeValues() throws {
        try withStore { store, defaults in
            store.set(99.0, for: SettingDefinitions.panelOpacity)
            #expect(defaults.object(forKey: "panelOpacity") as? Double == 1.0)
            store.set(1.0, for: SettingDefinitions.panelFontSize)
            #expect(defaults.object(forKey: "panelFontSize") as? Double == 10)
            store.set(.nan, for: SettingDefinitions.panelFontSize)
            #expect(defaults.object(forKey: "panelFontSize") as? Double == 14)
            store.set(1.0, for: SettingDefinitions.panelDefaultWidth)
            #expect(defaults.object(forKey: "panelDefaultWidth") as? Double == 320)
            store.set(99_999.0, for: SettingDefinitions.panelDefaultHeight)
            #expect(defaults.object(forKey: "panelDefaultHeight") as? Double == 4000)
            store.set(5000, for: SettingDefinitions.historyLimit)
            #expect(defaults.object(forKey: "historyLimit") as? Int == 1000)
            store.set(1, for: SettingDefinitions.historyLimit)
            #expect(defaults.object(forKey: "historyLimit") as? Int == 10)
        }
    }
}
