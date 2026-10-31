import AppKit
import Foundation
import Observation
import os
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsStoredValuesTests {
    private func makeStorage() throws -> (InMemoryDefaults, TemporaryDefaults) {
        let temporary = try TemporaryDefaults()
        return (temporary.defaults, temporary)
    }

    private func makeSettings(_ defaults: InMemoryDefaults) -> AppSettings {
        AppSettings(store: SettingsStore(defaults: defaults))
    }

    private func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func countChanges(of read: @escaping () -> Void, whileRunning body: () -> Void) -> Int {
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            read()
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        body()
        return changes.withLock { $0 }
    }

    // MARK: - 保存した値を読む(AC-2)

    @Test("AC-2: 今の版が保存した形の値を全部の項目に入れた保存先から作ると、保存した値のとおりに読む")
    func readsEveryStoredValue() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        let apps = [AutoShowApp(bundleIdentifier: "com.example.a", name: "A")]
        defaults.set(PanelShortcut.shiftReturn.storedValue, forKey: "commitShortcut")
        defaults.set(PanelShortcut.commandShiftReturn.storedValue, forKey: "commitAndSendShortcut")
        defaults.set("main", forKey: "panelScreen")
        defaults.set("selectedApps", forKey: "autoShowMode")
        defaults.set(try JSONEncoder().encode(apps), forKey: "autoShowApps")
        defaults.set("dark", forKey: "appTheme")
        defaults.set("Menlo-Regular", forKey: "panelFontName")
        defaults.set("Menlo", forKey: "panelFontFamilyName")
        defaults.set(20.0, forKey: "panelFontSize")
        defaults.set(0.6, forKey: "panelOpacity")
        defaults.set(["lineCount", "close"], forKey: "hiddenPanelStatusItems")
        defaults.set(true, forKey: "hidesMenuBarIcon")
        defaults.set(600.0, forKey: "panelDefaultWidth")
        defaults.set(400.0, forKey: "panelDefaultHeight")
        defaults.set("off", forKey: "animationMode")
        defaults.set(false, forKey: "insertionTargetOutlineShown")
        defaults.set(false, forKey: "showsDockIcon")
        defaults.set(false, forKey: "confirmsQuit")
        defaults.set(50, forKey: "historyLimit")
        defaults.set("sevenDays", forKey: "historyRetention")
        defaults.set("note", forKey: "newDraftMode")
        defaults.set(false, forKey: "checksForUpdatesAutomatically")
        defaults.set(true, forKey: "hasShownFirstLaunchTutorial")
        defaults.set(true, forKey: "sidebarIsOpen")
        defaults.set("history", forKey: "sidebarTab")
        defaults.set("/tmp/x", forKey: "lastExportDirectory")
        defaults.set(1_800_000_000.0, forKey: "lastUpdateCheckDate")
        defaults.set(true, forKey: "suppressesMoveToApplicationsPrompt")

        let settings = makeSettings(defaults)

        #expect(settings.commitKey == .shiftReturn)
        #expect(settings.commitAndSendKey == .commandShiftReturn)
        #expect(settings.panelScreen == .main)
        #expect(settings.autoShowMode == .selectedApps)
        #expect(settings.autoShowApps == apps)
        #expect(settings.theme == .dark)
        #expect(settings.panelFontName == "Menlo-Regular")
        #expect(settings.panelFontFamilyName == "Menlo")
        #expect(settings.panelFontSize == 20)
        #expect(settings.panelOpacity == 0.6)
        #expect(settings.hiddenPanelStatusItems == [.lineCount, .close])
        #expect(settings.isMenuBarIconShown == false)
        #expect(settings.panelDefaultWidth == 600)
        #expect(settings.panelDefaultHeight == 400)
        #expect(settings.animationMode == .off)
        #expect(settings.isInsertionTargetOutlineShown == false)
        #expect(settings.showsDockIcon == false)
        #expect(settings.confirmsQuit == false)
        #expect(settings.historyLimit == 50)
        #expect(settings.historyRetention == .sevenDays)
        #expect(settings.newDraftMode == .note)
        #expect(settings.checksForUpdatesAutomatically == false)
        #expect(settings.state.hasShownFirstLaunchTutorial)
        #expect(settings.state.isSidebarOpen)
        #expect(settings.state.sidebarTab == .history)
        #expect(settings.state.lastExportDirectoryPath == "/tmp/x")
        #expect(settings.state.lastUpdateCheckDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(settings.state.suppressesMoveToApplicationsPrompt)
    }

    @Test("AC-2: 旧形式の確定キーだけが保存されているときは、旧形式の読み替えと旧形式の初期値で読む")
    func readsLegacyCommitKeys() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        defaults.set("shiftEnter", forKey: "commitKey")

        let settings = makeSettings(defaults)

        #expect(settings.commitKey == .shiftReturn)
        #expect(settings.commitAndSendKey == PanelShortcut.legacyDefaultCommitAndSendKey)
    }

    @Test("AC-2: 旧形式の確定+送信キーだけが保存されているときは、確定キーが旧形式の初期値になる")
    func legacyCommitAndSendKeyChangesCommitDefault() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        defaults.set("commandEnter", forKey: "commitAndSendKey")

        let settings = makeSettings(defaults)

        #expect(settings.commitKey == PanelShortcut.legacyDefaultCommitKey)
        #expect(settings.commitAndSendKey == .commandReturn)
    }

    // MARK: - 初期値(AC-3)

    @Test("AC-3: 何も保存されていない保存先から作ると、全部の項目が今の初期値になり、何も保存しない")
    func readsDefaultsAndWritesNothing() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }

        let settings = makeSettings(defaults)

        #expect(settings.commitKey == .commandShiftReturn)
        #expect(settings.commitAndSendKey == .commandReturn)
        #expect(settings.panelScreen == .nearFocusedField)
        #expect(settings.autoShowMode == .off)
        #expect(settings.autoShowApps.isEmpty)
        #expect(settings.theme == .system)
        #expect(settings.panelFontName == nil)
        #expect(settings.panelFontFamilyName == nil)
        #expect(settings.panelFontSize == 14)
        #expect(settings.panelOpacity == 1.0)
        #expect(settings.hiddenPanelStatusItems.isEmpty)
        #expect(settings.isMenuBarIconShown)
        #expect(settings.panelDefaultWidth == 520)
        #expect(settings.panelDefaultHeight == 340)
        #expect(settings.animationMode == .on)
        #expect(settings.isInsertionTargetOutlineShown)
        #expect(settings.showsDockIcon)
        #expect(settings.confirmsQuit)
        #expect(settings.historyLimit == 200)
        #expect(settings.historyRetention == .forever)
        #expect(settings.newDraftMode == .insert)
        #expect(settings.checksForUpdatesAutomatically)
        #expect(settings.state.hasShownFirstLaunchTutorial == false)
        #expect(settings.state.isSidebarOpen == false)
        #expect(settings.state.sidebarTab == .drafts)
        #expect(settings.state.lastExportDirectoryPath == nil)
        #expect(settings.state.lastUpdateCheckDate == nil)
        #expect(settings.state.suppressesMoveToApplicationsPrompt == false)
        #expect(defaults.dictionaryRepresentation().isEmpty)
    }

    // MARK: - 範囲に収める(AC-5)

    @Test("AC-5: 文字サイズ・透明度・既定の幅・高さ・履歴の件数に範囲外の値を入れると、プロパティも保存も範囲の端になる")
    func outOfRangeValuesAreClamped() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        let settings = makeSettings(defaults)

        settings.panelFontSize = 5
        #expect(settings.panelFontSize == PanelTextStyle.fontSizeRange.lowerBound)
        #expect(defaults.double(forKey: "panelFontSize") == PanelTextStyle.fontSizeRange.lowerBound)
        settings.panelFontSize = 99
        #expect(settings.panelFontSize == PanelTextStyle.fontSizeRange.upperBound)
        #expect(defaults.double(forKey: "panelFontSize") == PanelTextStyle.fontSizeRange.upperBound)

        settings.panelOpacity = 0.1
        #expect(settings.panelOpacity == PanelTextStyle.opacityRange.lowerBound)
        #expect(defaults.double(forKey: "panelOpacity") == PanelTextStyle.opacityRange.lowerBound)
        settings.panelOpacity = 3
        #expect(settings.panelOpacity == PanelTextStyle.opacityRange.upperBound)
        #expect(defaults.double(forKey: "panelOpacity") == PanelTextStyle.opacityRange.upperBound)

        settings.panelDefaultWidth = 10
        #expect(settings.panelDefaultWidth == PanelMetrics.defaultWidthRange.lowerBound)
        #expect(defaults.double(forKey: "panelDefaultWidth") == PanelMetrics.defaultWidthRange.lowerBound)
        settings.panelDefaultWidth = 99_999
        #expect(settings.panelDefaultWidth == PanelMetrics.defaultWidthRange.upperBound)
        #expect(defaults.double(forKey: "panelDefaultWidth") == PanelMetrics.defaultWidthRange.upperBound)

        settings.panelDefaultHeight = 10
        #expect(settings.panelDefaultHeight == PanelMetrics.defaultHeightRange.lowerBound)
        #expect(defaults.double(forKey: "panelDefaultHeight") == PanelMetrics.defaultHeightRange.lowerBound)
        settings.panelDefaultHeight = 99_999
        #expect(settings.panelDefaultHeight == PanelMetrics.defaultHeightRange.upperBound)
        #expect(defaults.double(forKey: "panelDefaultHeight") == PanelMetrics.defaultHeightRange.upperBound)

        settings.historyLimit = 1
        #expect(settings.historyLimit == HistoryLimit.range.lowerBound)
        #expect(defaults.integer(forKey: "historyLimit") == HistoryLimit.range.lowerBound)
        settings.historyLimit = 5_000
        #expect(settings.historyLimit == HistoryLimit.range.upperBound)
        #expect(defaults.integer(forKey: "historyLimit") == HistoryLimit.range.upperBound)
    }

    @Test("AC-5: フォント名・ファミリー名に空文字を入れると nil になり、キーが消える")
    func emptyFontNamesBecomeNil() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        let settings = makeSettings(defaults)
        settings.panelFontName = "Menlo-Regular"
        #expect(defaults.string(forKey: "panelFontName") == "Menlo-Regular")

        settings.panelFontName = ""

        #expect(settings.panelFontName == nil)
        #expect(defaults.object(forKey: "panelFontName") == nil)

        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 12))
        settings.selectPanelFont(menlo)
        #expect(defaults.string(forKey: "panelFontFamilyName") == "Menlo")
        settings.resetPanelFontToSystem()
        #expect(settings.panelFontFamilyName == nil)
        #expect(defaults.object(forKey: "panelFontFamilyName") == nil)
    }

    @Test("AC-5: 範囲内の値を入れると、変化の通知は1回だけで値は書き換わらない")
    func inRangeValueNotifiesOnceAndKeepsValue() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        let settings = makeSettings(defaults)

        let opacityChanges = countChanges(of: { _ = settings.panelOpacity }) {
            settings.panelOpacity = 0.7
        }
        #expect(opacityChanges == 1)
        #expect(settings.panelOpacity == 0.7)
        #expect(defaults.double(forKey: "panelOpacity") == 0.7)

        let limitChanges = countChanges(of: { _ = settings.historyLimit }) {
            settings.historyLimit = 300
        }
        #expect(limitChanges == 1)
        #expect(settings.historyLimit == 300)
        #expect(defaults.integer(forKey: "historyLimit") == 300)
    }

    // MARK: - メニューバーのアイコン(AC-8)

    @Test("AC-8: isMenuBarIconShown を変えると、hidesMenuBarIcon に逆の真偽値が保存される")
    func menuBarIconIsStoredInverted() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        let settings = makeSettings(defaults)

        settings.isMenuBarIconShown = false
        #expect(isBoolean(defaults.object(forKey: "hidesMenuBarIcon")))
        #expect(defaults.object(forKey: "hidesMenuBarIcon") as? Bool == true)

        settings.isMenuBarIconShown = true
        #expect(isBoolean(defaults.object(forKey: "hidesMenuBarIcon")))
        #expect(defaults.object(forKey: "hidesMenuBarIcon") as? Bool == false)
    }

    @Test("AC-8: hidesMenuBarIcon に true が保存されていれば isMenuBarIconShown は false")
    func storedHiddenMeansNotShown() throws {
        let (defaults, temporary) = try makeStorage()
        defer { temporary.remove() }
        defaults.set(true, forKey: "hidesMenuBarIcon")
        #expect(makeSettings(defaults).isMenuBarIconShown == false)

        defaults.set(false, forKey: "hidesMenuBarIcon")
        #expect(makeSettings(defaults).isMenuBarIconShown)
    }
}
