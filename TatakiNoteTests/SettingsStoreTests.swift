import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsStoreTests {
    /// @note p0-1051
    private func makeSuite() throws -> (UserDefaults, String) {
        let name = UUID().uuidString
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    private func removeSuite(_ defaults: UserDefaults, name: String) {
        defaults.removePersistentDomain(forName: name)
    }

    @Test("AC-6, AC-9: 何も保存されていなければ、確定キーは登録なし、パネルを出す画面は「入力欄の近く」")
    func defaultsWhenNothingSaved() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.loadCommitShortcut() == nil)
        #expect(store.loadPanelScreen() == .nearFocusedField)
    }

    @Test("AC-2: 保存した確定キーとパネルを出す画面は、別の SettingsStore で読み込んでも同じ値")
    func savedValuesAreLoadedAgain() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        let shortcuts: [PanelShortcut?] = [
            .shiftReturn, .commandReturn, .commandShiftReturn, PanelShortcut(keyCode: 40, modifiers: [.command]), nil,
        ]
        for shortcut in shortcuts {
            SettingsStore(defaults: defaults).saveCommitShortcut(shortcut)
            #expect(SettingsStore(defaults: defaults).loadCommitShortcut() == shortcut, "\(String(describing: shortcut))")
        }
        for panelScreen in PanelScreen.allCases {
            SettingsStore(defaults: defaults).savePanelScreen(panelScreen)
            #expect(SettingsStore(defaults: defaults).loadPanelScreen() == panelScreen, "\(panelScreen)")
        }
    }

    @Test("AC-3, AC-6: 知らない文字列・型の違う値が保存されていれば、初期値として読み込む")
    func unknownValuesFallBackToDefaults() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let values: [Any] = ["unknown", "", "Both", 1, 3.5, true, ["both"], ["mouse": "main"], Data([0x01])]
        for value in values {
            defaults.set(value, forKey: "commitKey")
            defaults.set(value, forKey: "panelScreen")
            // @note p0-1052
            #expect(store.loadCommitShortcut() == .commandReturn, "\(value)")
            #expect(store.loadPanelScreen() == .nearFocusedField, "\(value)")
        }
    }

    @Test("AC-3: 以前の「両方」(both)が保存されていれば、落ちずに以前の初期値「⌘↩」として読み込む")
    func savedBothFallsBackToCommandEnter() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        defaults.set("both", forKey: "commitKey")
        #expect(store.loadCommitShortcut() == .commandReturn)
        #expect(AppSettings(store: store).commitKey == .commandReturn)
        // @note p0-1053
        #expect(defaults.string(forKey: "commitKey") == "both")
    }

    @Test("AC-9, AC-10: 以前のバージョンで保存した「Shift+Enter」「⌘Enter」は、そのまま引き継がれる")
    func previouslySavedValuesAreKept() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        // @note p0-1054
        defaults.set("shiftEnter", forKey: "commitKey")
        #expect(store.loadCommitShortcut() == .shiftReturn)
        #expect(AppSettings(store: store).commitKey == .shiftReturn)

        defaults.set("commandEnter", forKey: "commitKey")
        #expect(store.loadCommitShortcut() == .commandReturn)
        #expect(AppSettings(store: store).commitKey == .commandReturn)
    }

    @Test("AC-2, AC-10: 保存のキーは commitKey・panelScreen で、値は決めた文字列(以前の形式の読み替え)")
    func storageFormatIsFixed() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        // @note p0-1055
        #expect(PanelActionKey.allCases == [.shiftEnter, .commandEnter, .commandShiftEnter, PanelActionKey.none])

        let commitKeys: [(String, PanelShortcut?)] = [
            ("shiftEnter", .shiftReturn),
            ("commandEnter", .commandReturn),
            ("commandShiftEnter", .commandShiftReturn),
            ("none", nil),
        ]
        for (rawValue, expected) in commitKeys {
            defaults.set(rawValue, forKey: "commitKey")
            #expect(store.loadCommitShortcut() == expected, "\(rawValue)")
        }

        let panelScreens: [(PanelScreen, String)] = [
            (.mouse, "mouse"),
            (.targetWindow, "targetWindow"),
            (.main, "main"),
            (.nearFocusedField, "nearFocusedField"),
        ]
        for (panelScreen, expected) in panelScreens {
            store.savePanelScreen(panelScreen)
            #expect(defaults.string(forKey: "panelScreen") == expected)
        }

        // @note p0-1056
        defaults.set("commandEnter", forKey: "commitKey")
        defaults.set("targetWindow", forKey: "panelScreen")
        #expect(store.loadCommitShortcut() == .commandReturn)
        #expect(store.loadPanelScreen() == .targetWindow)
    }

    // MARK: - 確定+送信キー

    @Test("AC-9: 何も保存されていなければ、確定+送信キーは「⌘↩」")
    func commitAndSendKeyDefaultsToCommandReturn() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        #expect(SettingsStore(defaults: defaults).loadCommitAndSendShortcut() == .commandReturn)
        #expect(defaults.object(forKey: "commitAndSendKey") == nil)
    }

    @Test("AC-2, AC-10: 確定+送信キーの以前の形式(4つの決めた文字列)を読み替えられ、新しい形式の保存は別の SettingsStore で読んでも同じ値")
    func commitAndSendKeyStorageFormatIsFixed() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        let keys: [(String, PanelShortcut?)] = [
            ("shiftEnter", .shiftReturn),
            ("commandEnter", .commandReturn),
            ("commandShiftEnter", .commandShiftReturn),
            ("none", nil),
        ]
        for (rawValue, expected) in keys {
            defaults.set(rawValue, forKey: "commitAndSendKey")
            #expect(SettingsStore(defaults: defaults).loadCommitAndSendShortcut() == expected, "\(rawValue)")
        }

        // @note p0-1057
        defaults.set("commandShiftEnter", forKey: "commitAndSendKey")
        #expect(SettingsStore(defaults: defaults).loadCommitAndSendShortcut() == .commandShiftReturn)
        #expect(defaults.object(forKey: "commitKey") == nil)

        // @note p0-1058
        SettingsStore(defaults: defaults).saveCommitAndSendShortcut(.commandReturn)
        #expect(SettingsStore(defaults: defaults).loadCommitAndSendShortcut() == .commandReturn)
    }

    @Test("AC-2: 確定+送信キーに知らない文字列・型の違う値が保存されていれば、以前の初期値「登録なし」として読み込む")
    func unknownCommitAndSendKeyFallsBackToNone() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let values: [Any] = ["unknown", "", "both", "CommandEnter", 1, 3.5, true, ["commandEnter"], Data([0x01])]
        for value in values {
            defaults.set(value, forKey: "commitAndSendKey")
            #expect(store.loadCommitAndSendShortcut() == nil, "\(value)")
        }
    }

    // MARK: - 設定の見直しの土台

    /// @note p0-1059
    private let newKeys = [
        "appTheme", "panelFontName", "panelFontSize", "panelOpacity",
        "hiddenPanelStatusItems", "hidesMenuBarIcon", "panelDefaultWidth", "panelDefaultHeight",
    ]

    /// @note p0-1060
    private let existingKeys = ["commitKey", "commitAndSendKey", "panelScreen", "autoShowMode", "autoShowApps"]

    /// @note p0-1061
    private func storedNumber(_ defaults: UserDefaults, forKey key: String) -> Double? {
        (defaults.object(forKey: key) as? NSNumber)?.doubleValue
    }

    @Test("AC-1: 何も保存されていなければ、テーマはシステム・フォントは名前なし・文字サイズ 14・透明度 1.0・帯はすべて表示・アイコンを隠さない・既定の大きさ 520×340")
    func newSettingsDefaultWhenNothingSaved() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        #expect(store.loadAppTheme() == .system)
        #expect(store.loadPanelFontName() == nil)
        #expect(store.loadPanelFontSize() == 14)
        #expect(store.loadPanelOpacity() == 1.0)
        #expect(store.loadHiddenPanelStatusItems().isEmpty)
        #expect(store.loadHidesMenuBarIcon() == false)
        #expect(store.loadPanelDefaultWidth() == 520)
        #expect(store.loadPanelDefaultHeight() == 340)
        // @note p0-1062
        for key in newKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
    }

    @Test("AC-3, AC-31: テーマは system/light/dark の文字列、帯の非表示の項目は rawValue の配列で allCases の順、フォント名を nil・空文字にするとキーが消える")
    func newSettingsStorageFormatIsFixed() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let themes: [(AppTheme, String)] = [(.system, "system"), (.light, "light"), (.dark, "dark")]
        #expect(themes.map { $0.0 } == AppTheme.allCases)
        for (theme, expected) in themes {
            store.saveAppTheme(theme)
            #expect(defaults.string(forKey: "appTheme") == expected)
            #expect(store.loadAppTheme() == theme, "\(expected)")
        }

        let items: [(PanelStatusItem, String)] = [
            (.close, "close"),
            (.lineBreak, "lineBreak"),
            (.commit, "commit"),
            (.commitAndSend, "commitAndSend"),
            (.characterCount, "characterCount"),
            (.lineCount, "lineCount"),
        ]
        #expect(items.map { $0.0 } == PanelStatusItem.allCases)
        // @note p0-1063
        store.saveHiddenPanelStatusItems([.lineCount, .close, .lineBreak])
        #expect(defaults.stringArray(forKey: "hiddenPanelStatusItems") == ["close", "lineBreak", "lineCount"])
        #expect(store.loadHiddenPanelStatusItems() == [.close, .lineBreak, .lineCount])
        store.saveHiddenPanelStatusItems(Set(PanelStatusItem.allCases))
        #expect(defaults.stringArray(forKey: "hiddenPanelStatusItems") == items.map { $0.1 })
        store.saveHiddenPanelStatusItems([])
        #expect(defaults.stringArray(forKey: "hiddenPanelStatusItems") == [String]())

        store.savePanelFontName("Helvetica")
        #expect(defaults.string(forKey: "panelFontName") == "Helvetica")
        store.savePanelFontName(nil)
        #expect(defaults.object(forKey: "panelFontName") == nil)
        store.savePanelFontName("Helvetica")
        store.savePanelFontName("")
        #expect(defaults.object(forKey: "panelFontName") == nil)
    }

    @Test("AC-31: 以前の版の並び(lineBreak・close)で書かれた非表示の項目の配列も、同じ集合として読める")
    func hiddenPanelStatusItemsSavedInPreviousOrderAreStillReadable() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        defaults.set(["lineBreak", "close"], forKey: "hiddenPanelStatusItems")
        #expect(store.loadHiddenPanelStatusItems() == [.lineBreak, .close])
    }

    @Test("AC-4: テーマに知らない文字列(空文字・大文字違いの Dark を含む)・文字列でない値が保存されていれば「システム」")
    func brokenThemeFallsBackToSystem() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let values: [Any] = [
            "unknown", "", "Both", "Dark", "LIGHT", 1, 3.5, true, ["both"], ["dark"], ["mouse": "main"], Data([0x01]),
        ]
        for value in values {
            defaults.set(value, forKey: "appTheme")
            #expect(store.loadAppTheme() == .system, "\(value)")
            #expect(AppSettings(store: store).theme == .system, "\(value)")
        }
    }

    @Test("AC-4: フォント名は空文字・文字列でない値なら名前なし、知らない名前の文字列はその名前のまま読む")
    func brokenPanelFontNameFallsBackToNil() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, String?)] = [
            ("", nil),
            (1, nil),
            (3.5, nil),
            (true, nil),
            (["both"], nil),
            (["mouse": "main"], nil),
            (Data([0x01]), nil),
            ("unknown", "unknown"),
            ("TatakiNoteNoSuchFont-Regular", "TatakiNoteNoSuchFont-Regular"),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "panelFontName")
            #expect(store.loadPanelFontName() == expected, "\(value)")
            #expect(AppSettings(store: store).panelFontName == expected, "\(value)")
        }
    }

    @Test("AC-4: 帯の非表示の項目は配列でなければ空、配列の中の文字列でない要素と知らない名前だけを捨てて残りを読む")
    func brokenHiddenPanelStatusItemsKeepKnownNames() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Set<PanelStatusItem>)] = [
            ("unknown", []),
            ("", []),
            ("close", []),
            (1, []),
            (3.5, []),
            (true, []),
            (["mouse": "main"], []),
            (["close": "lineCount"], []),
            (Data([0x01]), []),
            (["both"], []),
            ([["close"]], []),
            (["lineCount", "unknown", "close"], [.lineCount, .close]),
            (["close", 1, true] as [Any], [.close]),
            (["Close", "LINECOUNT", "characterCount"], [.characterCount]),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "hiddenPanelStatusItems")
            #expect(store.loadHiddenPanelStatusItems() == expected, "\(value)")
            #expect(AppSettings(store: store).hiddenPanelStatusItems == expected, "\(value)")
        }
    }

    @Test("AC-4, AC-15: 新しいキー(既定の大きさを含む)が壊れていても、既存の設定は保存された値のまま読め、読むだけでは書き換えない")
    func existingSettingsSurviveBrokenNewKeys() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        defaults.set("shiftEnter", forKey: "commitKey")
        defaults.set("commandShiftEnter", forKey: "commitAndSendKey")
        defaults.set("targetWindow", forKey: "panelScreen")
        defaults.set("allApps", forKey: "autoShowMode")

        let values: [Any] = [
            "unknown", "", "Both", 1, 3.5, true, ["both"], ["mouse": "main"], Data([0x01]), -100, 100000,
        ]
        for value in values {
            for key in newKeys {
                defaults.set(value, forKey: key)
            }
            #expect(store.loadCommitShortcut() == .shiftReturn, "\(value)")
            #expect(store.loadCommitAndSendShortcut() == .commandShiftReturn, "\(value)")
            #expect(store.loadPanelScreen() == .targetWindow, "\(value)")
            #expect(store.loadAutoShowMode() == .allApps, "\(value)")

            let settings = AppSettings(store: store)
            #expect(settings.commitKey == .shiftReturn, "\(value)")
            #expect(settings.commitAndSendKey == .commandShiftReturn, "\(value)")
            #expect(settings.panelScreen == .targetWindow, "\(value)")
            #expect(settings.autoShowMode == .allApps, "\(value)")
            // @note p0-1064
            #expect(settings.panelDefaultWidth == 520, "\(value)")
            #expect(settings.panelDefaultHeight == 340, "\(value)")
        }
        #expect(defaults.string(forKey: "commitKey") == "shiftEnter")
        #expect(defaults.string(forKey: "commitAndSendKey") == "commandShiftEnter")
        #expect(defaults.string(forKey: "panelScreen") == "targetWindow")
        #expect(defaults.string(forKey: "autoShowMode") == "allApps")
        // @note p0-1065
        #expect(storedNumber(defaults, forKey: "panelDefaultWidth") == 100000)
        #expect(storedNumber(defaults, forKey: "panelDefaultHeight") == 100000)
    }

    @Test("AC-5: 文字サイズは 10〜32、透明度は 0.4〜1.0 に丸めて保存し、範囲外の値が保存されていても丸めて読む")
    func fontSizeAndOpacityAreClampedOnSaveAndLoad() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let fontSizes: [(Double, Double)] = [
            (5, 10), (9.9, 10), (10, 10), (14, 14), (15.5, 15.5), (32, 32), (32.1, 32), (50, 32), (-3, 10),
            (.nan, 14), (.infinity, 14), (-.infinity, 14),
        ]
        for (size, expected) in fontSizes {
            store.savePanelFontSize(size)
            #expect(storedNumber(defaults, forKey: "panelFontSize") == expected, "\(size)")
            #expect(store.loadPanelFontSize() == expected, "\(size)")
        }

        let opacities: [(Double, Double)] = [
            (0, 0.4), (0.39, 0.4), (0.4, 0.4), (0.75, 0.75), (1.0, 1.0), (1.5, 1.0), (-1, 0.4),
            (.nan, 1.0), (.infinity, 1.0), (-.infinity, 1.0),
        ]
        for (opacity, expected) in opacities {
            store.savePanelOpacity(opacity)
            #expect(storedNumber(defaults, forKey: "panelOpacity") == expected, "\(opacity)")
            #expect(store.loadPanelOpacity() == expected, "\(opacity)")
        }

        // @note p0-1066
        defaults.set(100, forKey: "panelFontSize")
        defaults.set(0.1, forKey: "panelOpacity")
        #expect(store.loadPanelFontSize() == 32)
        #expect(store.loadPanelOpacity() == 0.4)
        let settings = AppSettings(store: store)
        #expect(settings.panelFontSize == 32)
        #expect(settings.panelOpacity == 0.4)
    }

    @Test("AC-6, AC-7, AC-32: 「入力欄の近く」が初期値で、選択肢の並びは入力欄の近く・挿入先のウィンドウがある画面・マウスのある画面・メインの画面。保存済みの4つの値はどれも読んだまま")
    func nearFocusedFieldIsSavedAndLoaded() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }

        // AC-32
        // @note p0-1067
        #expect(PanelScreen.allCases == [.nearFocusedField, .targetWindow, .mouse, .main])
        #expect(PanelScreen.allCases.map(\.displayName) == ["入力欄の近く", "挿入先のウィンドウがある画面", "マウスのある画面", "メインの画面"])
        // AC-6
        // @note p0-1068
        #expect(PanelScreen.defaultValue == .nearFocusedField)
        #expect(SettingsStore(defaults: defaults).loadPanelScreen() == .nearFocusedField)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelScreen == .nearFocusedField)

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .mouse
        #expect(defaults.string(forKey: "panelScreen") == "mouse")
        #expect(SettingsStore(defaults: defaults).loadPanelScreen() == .mouse)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelScreen == .mouse)

        // AC-7
        // @note p0-1069
        let saved: [(String, PanelScreen)] = [
            ("mouse", .mouse),
            ("targetWindow", .targetWindow),
            ("main", .main),
            ("nearFocusedField", .nearFocusedField),
        ]
        for (raw, expected) in saved {
            defaults.set(raw, forKey: "panelScreen")
            #expect(SettingsStore(defaults: defaults).loadPanelScreen() == expected, "\(raw)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelScreen == expected, "\(raw)")
        }

        // @note p0-1070
        defaults.set("NearFocusedField", forKey: "panelScreen")
        #expect(SettingsStore(defaults: defaults).loadPanelScreen() == .nearFocusedField)
    }

    @Test("AC-11: 既存の設定のキー・初期値・保存の形・読み込みは、新しい設定を変えても変わらず、新しいキーと重ならない")
    func existingSettingsAreUnchanged() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        #expect([
            SettingsStore.Key.commitKey,
            SettingsStore.Key.commitAndSendKey,
            SettingsStore.Key.panelScreen,
            SettingsStore.Key.autoShowMode,
            SettingsStore.Key.autoShowApps,
        ] == existingKeys)
        #expect([
            SettingsStore.Key.appTheme,
            SettingsStore.Key.panelFontName,
            SettingsStore.Key.panelFontSize,
            SettingsStore.Key.panelOpacity,
            SettingsStore.Key.hiddenPanelStatusItems,
            SettingsStore.Key.hidesMenuBarIcon,
            SettingsStore.Key.panelDefaultWidth,
            SettingsStore.Key.panelDefaultHeight,
        ] == newKeys)
        let allKeys = existingKeys + newKeys + ["KeyboardShortcuts_togglePanel"]
        #expect(Set(allKeys).count == allKeys.count)

        // @note p0-1071
        let settings = AppSettings(store: store)
        settings.theme = .dark
        settings.panelFontName = "Helvetica"
        settings.panelFontSize = 20
        settings.panelOpacity = 0.5
        settings.hiddenPanelStatusItems = [.close]
        settings.hidesMenuBarIcon = true
        settings.panelDefaultWidth = 800
        settings.panelDefaultHeight = 600
        for key in existingKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
        #expect(store.loadCommitShortcut() == nil)
        #expect(store.loadCommitAndSendShortcut() == .commandReturn)
        #expect(store.loadPanelScreen() == .nearFocusedField)
        #expect(store.loadAutoShowMode() == .off)
        #expect(store.loadAutoShowApps().isEmpty)

        // @note p0-1072
        let chrome = AutoShowApp(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
        settings.commitKey = .shiftReturn
        settings.commitAndSendKey = .commandShiftReturn
        settings.panelScreen = .main
        settings.autoShowMode = .selectedApps
        settings.autoShowApps = [chrome]
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == PanelShortcut.shiftReturn.storedValue)
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)
        #expect(defaults.string(forKey: "panelScreen") == "main")
        #expect(defaults.string(forKey: "autoShowMode") == "selectedApps")
        let data = try #require(defaults.data(forKey: "autoShowApps"))
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [[String: String]])
        #expect(json == [["bundleIdentifier": "com.google.Chrome", "name": "Google Chrome"]])

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.commitKey == .shiftReturn)
        #expect(reloaded.commitAndSendKey == .commandShiftReturn)
        #expect(reloaded.panelScreen == .main)
        #expect(reloaded.autoShowMode == .selectedApps)
        #expect(reloaded.autoShowApps == [chrome])
        #expect(reloaded.theme == .dark)
        #expect(reloaded.panelFontName == "Helvetica")
        #expect(reloaded.panelFontSize == 20)
        #expect(reloaded.panelOpacity == 0.5)
        #expect(reloaded.hiddenPanelStatusItems == [.close])
        #expect(reloaded.hidesMenuBarIcon == true)
        #expect(reloaded.panelDefaultWidth == 800)
        #expect(reloaded.panelDefaultHeight == 600)
    }

    @Test("AC-13: 文字サイズは数値なら 10〜32 に丸めて読み、数値でない値(文字列の \"14\" を含む)と真偽値なら 14")
    func panelFontSizeIsReadByType() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Double)] = [
            ("unknown", 14),
            ("", 14),
            ("14", 14),
            ("20", 14),
            (true, 14),
            (false, 14),
            (["both"], 14),
            (["mouse": "main"], 14),
            (Data([0x01]), 14),
            (1, 10),
            (3.5, 10),
            (20, 20),
            (15.5, 15.5),
            (100, 32),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "panelFontSize")
            #expect(store.loadPanelFontSize() == expected, "\(value)")
            #expect(AppSettings(store: store).panelFontSize == expected, "\(value)")
        }
    }

    @Test("AC-13: 透明度は数値なら 0.4〜1.0 に丸めて読み、数値でない値と真偽値なら 1.0")
    func panelOpacityIsReadByType() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Double)] = [
            ("unknown", 1.0),
            ("", 1.0),
            ("0.5", 1.0),
            (true, 1.0),
            (false, 1.0),
            (["both"], 1.0),
            (["mouse": "main"], 1.0),
            (Data([0x01]), 1.0),
            (0, 0.4),
            (0.5, 0.5),
            (1, 1.0),
            (3.5, 1.0),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "panelOpacity")
            #expect(store.loadPanelOpacity() == expected, "\(value)")
            #expect(AppSettings(store: store).panelOpacity == expected, "\(value)")
        }
    }

    @Test("AC-13: メニューバーのアイコンを隠す設定は、真偽値で保存されているときだけその値を読み、数値の 0・1 や文字列の \"YES\" などはオフ")
    func hidesMenuBarIconIsReadOnlyFromBoolean() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Bool)] = [
            (true, true),
            (false, false),
            (1, false),
            (0, false),
            (3.5, false),
            ("YES", false),
            ("true", false),
            (["both"], false),
            (["mouse": "main"], false),
            (Data([0x01]), false),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "hidesMenuBarIcon")
            #expect(store.loadHidesMenuBarIcon() == expected, "\(value)")
            #expect(AppSettings(store: store).hidesMenuBarIcon == expected, "\(value)")
        }

        // @note p0-1073
        store.saveHidesMenuBarIcon(true)
        #expect(store.loadHidesMenuBarIcon() == true)
        store.saveHidesMenuBarIcon(false)
        #expect(store.loadHidesMenuBarIcon() == false)
    }

    @Test("AC-14: SettingsStore に直接保存しても、既定の大きさは幅 320〜4000・高さ 160〜4000 に丸めて書く(NaN・無限大は初期値)")
    func panelDefaultSizeIsClampedOnSave() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let widths: [(Double, Double)] = [
            (100, 320), (320, 320), (800, 800), (600.5, 600.5), (4000, 4000), (5000, 4000),
            (.nan, 520), (.infinity, 520), (-.infinity, 520),
        ]
        for (width, expected) in widths {
            store.savePanelDefaultWidth(width)
            #expect(storedNumber(defaults, forKey: "panelDefaultWidth") == expected, "\(width)")
            #expect(store.loadPanelDefaultWidth() == expected, "\(width)")
        }

        let heights: [(Double, Double)] = [
            (50, 160), (160, 160), (500, 500), (4000, 4000), (5000, 4000),
            (.nan, 340), (.infinity, 340), (-.infinity, 340),
        ]
        for (height, expected) in heights {
            store.savePanelDefaultHeight(height)
            #expect(storedNumber(defaults, forKey: "panelDefaultHeight") == expected, "\(height)")
            #expect(store.loadPanelDefaultHeight() == expected, "\(height)")
        }
    }

    @Test("AC-15: 既定の幅は、範囲外・壊れた値・型の違う値(文字列の \"520\"・真偽値を含む)なら丸めずに 520、範囲の端と範囲内の値はそのまま読む")
    func panelDefaultWidthLoadsOnlyValuesInRange() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Double)] = [
            ("unknown", 520),
            ("", 520),
            ("Both", 520),
            ("520", 520),
            ("800", 520),
            (true, 520),
            (false, 520),
            (["both"], 520),
            (["mouse": "main"], 520),
            (Data([0x01]), 520),
            (0, 520),
            (1, 520),
            (3.5, 520),
            (-100, 520),
            (319, 520),
            (4001, 520),
            (100000, 520),
            (320, 320),
            (800, 800),
            (600.5, 600.5),
            (4000, 4000),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "panelDefaultWidth")
            #expect(store.loadPanelDefaultWidth() == expected, "\(value)")
            #expect(AppSettings(store: store).panelDefaultWidth == expected, "\(value)")
        }
    }

    @Test("AC-15: 既定の高さは、範囲外・壊れた値・型の違う値(文字列・真偽値を含む)なら丸めずに 340、範囲の端と範囲内の値はそのまま読む")
    func panelDefaultHeightLoadsOnlyValuesInRange() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let cases: [(Any, Double)] = [
            ("unknown", 340),
            ("", 340),
            ("Both", 340),
            ("340", 340),
            ("500", 340),
            (true, 340),
            (false, 340),
            (["both"], 340),
            (["mouse": "main"], 340),
            (Data([0x01]), 340),
            (0, 340),
            (1, 340),
            (3.5, 340),
            (-100, 340),
            (159, 340),
            (4001, 340),
            (100000, 340),
            (160, 160),
            (500, 500),
            (250.5, 250.5),
            (4000, 4000),
        ]
        for (value, expected) in cases {
            defaults.set(value, forKey: "panelDefaultHeight")
            #expect(store.loadPanelDefaultHeight() == expected, "\(value)")
            #expect(AppSettings(store: store).panelDefaultHeight == expected, "\(value)")
        }
    }

    @Test("AC-15: 既定の大きさの幅と高さはキーごとに読み、片方だけが壊れていればその片方だけが初期値")
    func panelDefaultWidthAndHeightAreLoadedSeparately() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        defaults.set("broken", forKey: "panelDefaultWidth")
        defaults.set(500, forKey: "panelDefaultHeight")
        #expect(store.loadPanelDefaultWidth() == 520)
        #expect(store.loadPanelDefaultHeight() == 500)
        #expect(AppSettings(store: store).panelDefaultSize == CGSize(width: 520, height: 500))

        defaults.set(800, forKey: "panelDefaultWidth")
        defaults.set(4001, forKey: "panelDefaultHeight")
        #expect(store.loadPanelDefaultWidth() == 800)
        #expect(store.loadPanelDefaultHeight() == 340)
        #expect(AppSettings(store: store).panelDefaultSize == CGSize(width: 800, height: 340))
    }

    // MARK: - 確定キー・確定+送信キー(新しい保存形式)

    @Test("AC-10: 以前の形式(Shift+Enter・⌘Enter・Shift+⌘Enter・なし)は、それぞれ ⇧↩・⌘↩・⇧⌘↩・登録なしとして読み込まれ、以前の保存は消えない")
    func legacyCommitShortcutsAreTranslated() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let legacyCases: [(String, PanelShortcut?)] = [
            ("shiftEnter", .shiftReturn),
            ("commandEnter", .commandReturn),
            ("commandShiftEnter", .commandShiftReturn),
            ("none", nil),
        ]
        for (legacy, expected) in legacyCases {
            defaults.set(legacy, forKey: "commitKey")
            #expect(store.loadCommitShortcut() == expected, "\(legacy)")
            // @note p0-1074
            #expect(defaults.string(forKey: "commitKey") == legacy, "\(legacy)")
            // @note p0-1075
            #expect(defaults.object(forKey: "commitShortcut") == nil, "\(legacy)")
        }
    }

    @Test("AC-10: 新しい形式の保存があれば、旧キーがあってもそちらを使う")
    func newCommitShortcutTakesPriorityOverLegacy() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        defaults.set("shiftEnter", forKey: "commitKey")
        store.saveCommitShortcut(.commandReturn)
        #expect(store.loadCommitShortcut() == .commandReturn)
        // @note p0-1076
        #expect(defaults.string(forKey: "commitKey") == "shiftEnter")

        store.saveCommitShortcut(nil)
        #expect(store.loadCommitShortcut() == nil)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == [])
    }

    @Test("AC-22: 新しい形式が壊れている(配列でない・要素が2つの整数でない・修飾キーが無い)と初期値。旧キーが無ければ確定は登録なし・確定+送信は⌘↩、旧キーがあれば確定は⌘↩・確定+送信は登録なし")
    func brokenNewFormatFallsBackToDefaults() throws {
        let (defaults, name) = try makeSuite()
        defer { removeSuite(defaults, name: name) }
        let store = SettingsStore(defaults: defaults)

        let brokenValues: [Any] = [
            "unknown", 1, 3.5, true, ["mouse": "main"], Data([0x01]),
            [36], [36, 1_048_576, 0], ["36", 1_048_576], [36, 0], [36, -1],
        ]
        for value in brokenValues {
            defaults.set(value, forKey: "commitShortcut")
            defaults.set(value, forKey: "commitAndSendShortcut")
            #expect(store.loadCommitShortcut() == PanelShortcut.defaultCommitKey, "\(value)")
            #expect(store.loadCommitAndSendShortcut() == PanelShortcut.defaultCommitAndSendKey, "\(value)")
        }

        // @note p0-1077
        defaults.set("shiftEnter", forKey: "commitKey")
        for value in brokenValues {
            defaults.set(value, forKey: "commitShortcut")
            defaults.set(value, forKey: "commitAndSendShortcut")
            #expect(store.loadCommitShortcut() == PanelShortcut.legacyDefaultCommitKey, "\(value)")
            #expect(store.loadCommitAndSendShortcut() == PanelShortcut.legacyDefaultCommitAndSendKey, "\(value)")
        }
    }

    @Test("AC-33: 以前の版で片方だけ保存している人は、保存していない方も以前の初期値(確定 ⌘↩・確定+送信 登録なし)で読まれ、新しい初期値に変わらない")
    func legacyPartialSavesFallBackToLegacyDefaultForTheOtherKey() throws {
        // @note p0-1078
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == nil)
            #expect(store.loadCommitAndSendShortcut() == .commandReturn)
        }

        // @note p0-1079
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set("shiftEnter", forKey: "commitKey")
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == .shiftReturn)
            #expect(store.loadCommitAndSendShortcut() == nil)
        }

        // @note p0-1080
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set("commandEnter", forKey: "commitKey")
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == .commandReturn)
            #expect(store.loadCommitAndSendShortcut() == nil)
        }

        // @note p0-1081
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set("commandShiftEnter", forKey: "commitAndSendKey")
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == .commandReturn)
            #expect(store.loadCommitAndSendShortcut() == .commandShiftReturn)
        }

        // @note p0-1082
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set("both", forKey: "commitKey")
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == .commandReturn)
            #expect(store.loadCommitAndSendShortcut() == nil)
        }

        // @note p0-1083
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set([40, 1_048_576], forKey: "commitShortcut")
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadCommitShortcut() == PanelShortcut(keyCode: 40, modifiers: [.command]))
            #expect(store.loadCommitAndSendShortcut() == .commandReturn)
        }

        // @note p0-1084
        do {
            let (defaults, name) = try makeSuite()
            defer { removeSuite(defaults, name: name) }
            defaults.set("shiftEnter", forKey: "commitKey")
            let store = SettingsStore(defaults: defaults)
            store.saveCommitAndSendShortcut(PanelShortcut(keyCode: 40, modifiers: [.command]))
            #expect(store.loadCommitShortcut() == .shiftReturn)
            #expect(store.loadCommitAndSendShortcut() == PanelShortcut(keyCode: 40, modifiers: [.command]))
        }
    }
}
