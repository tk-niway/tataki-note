import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsTests {
    @Test("AC-2: 変えた値は、同じ保存先で作り直した AppSettings でも同じ値")
    func changedValuesSurviveRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = .commandReturn
        settings.panelScreen = .targetWindow

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.commitKey == .commandReturn)
        #expect(reloaded.panelScreen == .targetWindow)

        // @note p0-729
        reloaded.commitKey = .shiftReturn
        reloaded.panelScreen = .main
        let reloadedAgain = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloadedAgain.commitKey == .shiftReturn)
        #expect(reloadedAgain.panelScreen == .main)
    }

    @Test("AC-9, AC-11: 新しい候補(⇧⌘↩・登録なし)も、同じ保存先で作り直した AppSettings で同じ値")
    func newCommitKeysSurviveRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.commitKey = .commandShiftReturn
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).commitKey == .commandShiftReturn)

        // @note p0-730
        settings.commitKey = nil
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).commitKey == nil)
    }

    @Test("AC-1, AC-2, AC-6, AC-9: 作っただけでは何も保存せず、初期値を読む")
    func initDoesNotSave() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.commitKey == nil)
        #expect(settings.panelScreen == .nearFocusedField)
        #expect(defaults.object(forKey: "commitKey") == nil)
        #expect(defaults.object(forKey: "commitShortcut") == nil)
        #expect(defaults.object(forKey: "panelScreen") == nil)
    }

    // MARK: - 確定+送信キー

    @Test("AC-9, AC-11: 確定+送信キーは初期値「⌘↩」で、作っただけでは保存しない。変えると保存され、作り直しても残る")
    func commitAndSendKeyIsSavedAndSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.commitAndSendKey == .commandReturn)
        #expect(defaults.object(forKey: "commitAndSendShortcut") == nil)

        settings.commitAndSendKey = .commandShiftReturn
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).commitAndSendKey == .commandShiftReturn)

        // @note p0-731
        settings.commitAndSendKey = nil
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == [])
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).commitAndSendKey == nil)
    }

    @Test("AC-14: 確定で使っているキーは確定+送信に選べず(値も保存も変わらない)、逆も同じ。登録なしはどちらでも選べる")
    func selectRejectsKeyUsedByTheOtherAction() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.commitAndSendKey == .commandReturn)

        // @note p0-732
        #expect(settings.selectCommitKey(.commandReturn) == false)
        #expect(settings.commitKey == nil)
        #expect(defaults.object(forKey: "commitShortcut") == nil)

        // @note p0-733
        #expect(settings.selectCommitKey(.commandShiftReturn) == true)
        #expect(settings.commitKey == .commandShiftReturn)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)

        // @note p0-734
        #expect(settings.selectCommitAndSendKey(.commandShiftReturn) == false)
        #expect(settings.commitAndSendKey == .commandReturn)

        // @note p0-735
        #expect(settings.selectCommitAndSendKey(nil) == true)
        #expect(settings.commitAndSendKey == nil)
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == [])

        // @note p0-736
        #expect(settings.selectCommitKey(nil) == true)
        #expect(settings.commitKey == nil)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == [])

        // @note p0-737
        #expect(settings.selectCommitKey(.shiftReturn) == true)
        #expect(settings.commitKey == .shiftReturn)
        // @note p0-738
        #expect(settings.selectCommitAndSendKey(.shiftReturn) == false)
        #expect(settings.commitAndSendKey == nil)
    }

    // MARK: - 設定の見直しの土台

    /// @note p0-739
    private let newKeys = [
        "appTheme", "panelFontName", "panelFontSize", "panelOpacity",
        "hiddenPanelStatusItems", "hidesMenuBarIcon", "panelDefaultWidth", "panelDefaultHeight",
    ]

    /// @note p0-740
    private func storedNumber(_ defaults: UserDefaults, forKey key: String) -> Double? {
        (defaults.object(forKey: key) as? NSNumber)?.doubleValue
    }

    @Test("AC-1: 新しい設定の初期値はテーマ「システム」・フォント名なし・文字サイズ 14・透明度 1.0・帯はすべて表示・アイコンを隠さない・既定の大きさ 520×340 で、作っただけでは新しいキーに何も保存しない")
    func newSettingsDefaultsAndInitDoesNotSave() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.theme == .system)
        #expect(settings.panelFontName == nil)
        #expect(settings.panelFontSize == 14)
        #expect(settings.panelOpacity == 1.0)
        #expect(settings.hiddenPanelStatusItems.isEmpty)
        #expect(settings.hidesMenuBarIcon == false)
        #expect(settings.panelDefaultWidth == 520)
        #expect(settings.panelDefaultHeight == 340)
        #expect(settings.panelDefaultSize == CGSize(width: 520, height: 340))
        #expect(settings.panelFont.fontName == NSFont.systemFont(ofSize: 14).fontName)
        #expect(settings.panelFont.pointSize == 14)
        for key in newKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
    }

    @Test("AC-2: 新しい設定を変えると保存され、同じ保存先で作り直した AppSettings でも同じ値")
    func newSettingsSurviveRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.theme = .dark
        settings.panelFontName = "Helvetica"
        settings.panelFontSize = 18
        settings.panelOpacity = 0.7
        settings.hiddenPanelStatusItems = [.close, .lineCount]
        settings.hidesMenuBarIcon = true
        settings.panelDefaultWidth = 800
        settings.panelDefaultHeight = 600.5
        for key in newKeys {
            #expect(defaults.object(forKey: key) != nil, "\(key)")
        }

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.theme == .dark)
        #expect(reloaded.panelFontName == "Helvetica")
        #expect(reloaded.panelFontSize == 18)
        #expect(reloaded.panelOpacity == 0.7)
        #expect(reloaded.hiddenPanelStatusItems == [.close, .lineCount])
        #expect(reloaded.hidesMenuBarIcon == true)
        #expect(reloaded.panelDefaultWidth == 800)
        #expect(reloaded.panelDefaultHeight == 600.5)
        #expect(reloaded.panelDefaultSize == CGSize(width: 800, height: 600.5))

        // @note p0-741
        reloaded.theme = .light
        reloaded.panelFontName = nil
        reloaded.panelFontSize = 14
        reloaded.panelOpacity = 1.0
        reloaded.hiddenPanelStatusItems = []
        reloaded.hidesMenuBarIcon = false
        reloaded.panelDefaultWidth = 320
        reloaded.panelDefaultHeight = 4000
        let reloadedAgain = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloadedAgain.theme == .light)
        #expect(reloadedAgain.panelFontName == nil)
        #expect(reloadedAgain.panelFontSize == 14)
        #expect(reloadedAgain.panelOpacity == 1.0)
        #expect(reloadedAgain.hiddenPanelStatusItems.isEmpty)
        #expect(reloadedAgain.hidesMenuBarIcon == false)
        #expect(reloadedAgain.panelDefaultWidth == 320)
        #expect(reloadedAgain.panelDefaultHeight == 4000)
    }

    @Test("AC-3: panelFontName に空文字を代入すると nil になり、保存のキーが消える")
    func emptyPanelFontNameBecomesNil() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelFontName = "Helvetica"
        #expect(defaults.string(forKey: "panelFontName") == "Helvetica")

        settings.panelFontName = ""
        #expect(settings.panelFontName == nil)
        #expect(defaults.object(forKey: "panelFontName") == nil)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelFontName == nil)

        settings.panelFontName = "Helvetica"
        settings.panelFontName = nil
        #expect(defaults.object(forKey: "panelFontName") == nil)
    }

    @Test("AC-5: 文字サイズ・透明度に範囲外の値を代入すると丸めて保存し、NaN・無限大は初期値(14・1.0)になる")
    func fontSizeAndOpacityAreClampedOnAssignment() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        let fontSizes: [(Double, Double)] = [
            (5, 10), (10, 10), (20, 20), (15.5, 15.5), (32, 32), (50, 32), (-1, 10),
            (.nan, 14), (.infinity, 14), (-.infinity, 14),
        ]
        for (size, expected) in fontSizes {
            // @note p0-742
            settings.panelFontSize = 25
            settings.panelFontSize = size
            #expect(settings.panelFontSize == expected, "\(size)")
            #expect(storedNumber(defaults, forKey: "panelFontSize") == expected, "\(size)")
        }

        let opacities: [(Double, Double)] = [
            (0, 0.4), (0.4, 0.4), (0.5, 0.5), (1.0, 1.0), (1.5, 1.0), (-1, 0.4),
            (.nan, 1.0), (.infinity, 1.0), (-.infinity, 1.0),
        ]
        for (opacity, expected) in opacities {
            settings.panelOpacity = 0.6
            settings.panelOpacity = opacity
            #expect(settings.panelOpacity == expected, "\(opacity)")
            #expect(storedNumber(defaults, forKey: "panelOpacity") == expected, "\(opacity)")
        }

        // @note p0-743
        settings.panelFontSize = 100
        settings.panelOpacity = 0.1
        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.panelFontSize == 32)
        #expect(reloaded.panelOpacity == 0.4)
        #expect(reloaded.panelFont.pointSize == 32)
    }

    @Test("AC-9, AC-17, AC-31: 帯に出す項目は allCases の順で、非表示にした項目と登録なしのキーを出さない。1つずつ切り替えて保存でき、すべて非表示なら空")
    func panelStatusItemsFollowSettings() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        // @note p0-744
        #expect(settings.panelStatusItems == [.close, .lineBreak, .commitAndSend, .characterCount, .lineCount])

        settings.commitKey = .shiftReturn
        #expect(settings.panelStatusItems == PanelStatusItem.allCases)

        // @note p0-745
        settings.setPanelStatusItem(.close, isVisible: false)
        #expect(settings.hiddenPanelStatusItems == [.close])
        #expect(settings.panelStatusItems == [.lineBreak, .commit, .commitAndSend, .characterCount, .lineCount])
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hiddenPanelStatusItems == [.close])

        // @note p0-746
        settings.setPanelStatusItem(.close, isVisible: false)
        #expect(settings.hiddenPanelStatusItems == [.close])
        settings.setPanelStatusItem(.close, isVisible: true)
        #expect(settings.hiddenPanelStatusItems.isEmpty)
        #expect(settings.panelStatusItems == PanelStatusItem.allCases)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hiddenPanelStatusItems.isEmpty)

        // @note p0-747
        settings.commitAndSendKey = nil
        #expect(settings.hiddenPanelStatusItems.isEmpty)
        #expect(settings.panelStatusItems == [.close, .lineBreak, .commit, .characterCount, .lineCount])

        // @note p0-748
        for item in PanelStatusItem.allCases {
            settings.setPanelStatusItem(item, isVisible: false)
        }
        #expect(settings.hiddenPanelStatusItems == Set(PanelStatusItem.allCases))
        #expect(settings.panelStatusItems.isEmpty)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelStatusItems.isEmpty)
    }

    @Test("AC-14: 既定の大きさの幅・高さに代入すると範囲(幅 320〜4000・高さ 160〜4000)に丸めて保存し、NaN・無限大は初期値。panelDefaultSize は幅と高さの組")
    func panelDefaultSizeIsClampedOnAssignment() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        let widths: [(Double, Double)] = [
            (100, 320), (320, 320), (800, 800), (600.5, 600.5), (4000, 4000), (5000, 4000),
            (.nan, 520), (.infinity, 520), (-.infinity, 520),
        ]
        for (width, expected) in widths {
            // @note p0-749
            settings.panelDefaultWidth = 1000
            settings.panelDefaultWidth = width
            #expect(settings.panelDefaultWidth == expected, "\(width)")
            #expect(storedNumber(defaults, forKey: "panelDefaultWidth") == expected, "\(width)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelDefaultWidth == expected, "\(width)")
        }

        let heights: [(Double, Double)] = [
            (50, 160), (160, 160), (500, 500), (4000, 4000), (5000, 4000),
            (.nan, 340), (.infinity, 340), (-.infinity, 340),
        ]
        for (height, expected) in heights {
            settings.panelDefaultHeight = 1000
            settings.panelDefaultHeight = height
            #expect(settings.panelDefaultHeight == expected, "\(height)")
            #expect(storedNumber(defaults, forKey: "panelDefaultHeight") == expected, "\(height)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelDefaultHeight == expected, "\(height)")
        }

        settings.panelDefaultWidth = 700
        settings.panelDefaultHeight = 450.5
        #expect(settings.panelDefaultSize == CGSize(width: 700, height: 450.5))
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).panelDefaultSize == CGSize(width: 700, height: 450.5))
    }

    // MARK: - メニューバーのアイコン

    @Test("AC-9: アイコンを出すか(isMenuBarIconShown)は隠すか(hidesMenuBarIcon)の逆で、初期値は出す。書くと隠すかが逆の値で保存され、作り直しても残る")
    func menuBarIconShownIsInverseOfHides() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.isMenuBarIconShown == true)
        #expect(settings.hidesMenuBarIcon == false)

        // @note p0-750
        settings.isMenuBarIconShown = false
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.object(forKey: "hidesMenuBarIcon") != nil)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.isMenuBarIconShown == false)
        #expect(reloaded.hidesMenuBarIcon == true)

        // @note p0-751
        settings.isMenuBarIconShown = true
        #expect(settings.hidesMenuBarIcon == false)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == false)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).isMenuBarIconShown == true)

        // @note p0-752
        settings.hidesMenuBarIcon = true
        #expect(settings.isMenuBarIconShown == false)
    }
}
