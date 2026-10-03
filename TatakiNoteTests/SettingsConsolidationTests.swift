import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SettingsConsolidationTests {
    private struct ClampCase {
        let input: Double
        let expected: Double
    }

    private func expectClamping(
        _ cases: [ClampCase],
        range: ClosedRange<Double>,
        fallback: Double,
        clamp: (Double) -> Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for item in cases {
            #expect(clamp(item.input) == item.expected, sourceLocation: sourceLocation)
            #expect(
                range.clamping(item.input, nonFiniteFallback: fallback) == item.expected,
                sourceLocation: sourceLocation
            )
        }
    }

    @Test("AC-1: 文字サイズは 10〜32 に収まり、NaN・±∞ は 14 になる")
    func fontSizeClamping() {
        expectClamping(
            [
                ClampCase(input: 18, expected: 18),
                ClampCase(input: 10, expected: 10),
                ClampCase(input: 32, expected: 32),
                ClampCase(input: 9.99, expected: 10),
                ClampCase(input: -5, expected: 10),
                ClampCase(input: 32.01, expected: 32),
                ClampCase(input: 1000, expected: 32),
                ClampCase(input: .nan, expected: 14),
                ClampCase(input: .infinity, expected: 14),
                ClampCase(input: -.infinity, expected: 14)
            ],
            range: PanelTextStyle.fontSizeRange,
            fallback: PanelTextStyle.defaultFontSize,
            clamp: PanelTextStyle.clampedFontSize
        )
    }

    @Test("AC-1: 透明度は 0.4〜1.0 に収まり、NaN・±∞ は 1.0 になる")
    func opacityClamping() {
        expectClamping(
            [
                ClampCase(input: 0.7, expected: 0.7),
                ClampCase(input: 0.4, expected: 0.4),
                ClampCase(input: 1.0, expected: 1.0),
                ClampCase(input: 0.39, expected: 0.4),
                ClampCase(input: 0, expected: 0.4),
                ClampCase(input: -3, expected: 0.4),
                ClampCase(input: 1.01, expected: 1.0),
                ClampCase(input: 50, expected: 1.0),
                ClampCase(input: .nan, expected: 1.0),
                ClampCase(input: .infinity, expected: 1.0),
                ClampCase(input: -.infinity, expected: 1.0)
            ],
            range: PanelTextStyle.opacityRange,
            fallback: PanelTextStyle.defaultOpacity,
            clamp: PanelTextStyle.clampedOpacity
        )
    }

    @Test("AC-1: パネルの既定の幅は 320〜4000 に収まり、NaN・±∞ は 520 になる")
    func defaultWidthClamping() {
        expectClamping(
            [
                ClampCase(input: 600, expected: 600),
                ClampCase(input: 320, expected: 320),
                ClampCase(input: 4000, expected: 4000),
                ClampCase(input: 319, expected: 320),
                ClampCase(input: 0, expected: 320),
                ClampCase(input: -100, expected: 320),
                ClampCase(input: 4001, expected: 4000),
                ClampCase(input: 100_000, expected: 4000),
                ClampCase(input: .nan, expected: 520),
                ClampCase(input: .infinity, expected: 520),
                ClampCase(input: -.infinity, expected: 520)
            ],
            range: PanelMetrics.defaultWidthRange,
            fallback: 520,
            clamp: PanelMetrics.clampedDefaultWidth
        )
    }

    @Test("AC-1: パネルの既定の高さは 160〜4000 に収まり、NaN・±∞ は 340 になる")
    func defaultHeightClamping() {
        expectClamping(
            [
                ClampCase(input: 400, expected: 400),
                ClampCase(input: 160, expected: 160),
                ClampCase(input: 4000, expected: 4000),
                ClampCase(input: 159, expected: 160),
                ClampCase(input: 0, expected: 160),
                ClampCase(input: -100, expected: 160),
                ClampCase(input: 4001, expected: 4000),
                ClampCase(input: 100_000, expected: 4000),
                ClampCase(input: .nan, expected: 340),
                ClampCase(input: .infinity, expected: 340),
                ClampCase(input: -.infinity, expected: 340)
            ],
            range: PanelMetrics.defaultHeightRange,
            fallback: 340,
            clamp: PanelMetrics.clampedDefaultHeight
        )
    }

    @Test("AC-2: 各設定を保存して別の SettingsStore で読み直すと、同じ値になる")
    func savedValuesRoundTrip() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let apps = [AutoShowApp(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit")]
        let writer = SettingsStore(defaults: temp.defaults)
        writer.savePanelScreen(.mouse)
        writer.saveAutoShowMode(.selectedApps)
        writer.saveAutoShowApps(apps)
        writer.saveAppTheme(.dark)
        writer.savePanelFontName("Menlo-Regular")
        writer.savePanelFontFamilyName("Menlo")
        writer.savePanelFontSize(18)
        writer.savePanelOpacity(0.6)
        writer.saveHiddenPanelStatusItems([.lineBreak, .close])
        writer.saveHidesMenuBarIcon(true)
        writer.saveHasShownFirstLaunchTutorial(true)
        writer.savePanelDefaultWidth(600)
        writer.savePanelDefaultHeight(400)
        writer.saveCommitShortcut(.shiftReturn)
        writer.saveCommitAndSendShortcut(nil)

        let reader = SettingsStore(defaults: temp.defaults)
        #expect(reader.loadPanelScreen() == .mouse)
        #expect(reader.loadAutoShowMode() == .selectedApps)
        #expect(reader.loadAutoShowApps() == apps)
        #expect(reader.loadAppTheme() == .dark)
        #expect(reader.loadPanelFontName() == "Menlo-Regular")
        #expect(reader.loadPanelFontFamilyName() == "Menlo")
        #expect(reader.loadPanelFontSize() == 18)
        #expect(reader.loadPanelOpacity() == 0.6)
        #expect(reader.loadHiddenPanelStatusItems() == [.lineBreak, .close])
        #expect(reader.loadHidesMenuBarIcon())
        #expect(reader.loadHasShownFirstLaunchTutorial())
        #expect(reader.loadPanelDefaultWidth() == 600)
        #expect(reader.loadPanelDefaultHeight() == 400)
        #expect(reader.loadCommitShortcut() == .shiftReturn)
        #expect(reader.loadCommitAndSendShortcut() == nil)
    }

    @Test("AC-2: 保存のキーと値の型(文字列・数値・真偽値・配列・データ)が今と同じ")
    func storedKeysAndValueTypes() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults

        let store = SettingsStore(defaults: defaults)
        store.savePanelScreen(.main)
        store.saveAutoShowMode(.allApps)
        store.saveAutoShowApps([AutoShowApp(bundleIdentifier: "com.example.app", name: "Example")])
        store.saveAppTheme(.light)
        store.savePanelFontName("Menlo-Regular")
        store.savePanelFontFamilyName("Menlo")
        store.savePanelFontSize(20)
        store.savePanelOpacity(0.5)
        store.saveHiddenPanelStatusItems([.lineCount])
        store.saveHidesMenuBarIcon(true)
        store.saveHasShownFirstLaunchTutorial(true)
        store.savePanelDefaultWidth(700)
        store.savePanelDefaultHeight(500)
        store.saveCommitShortcut(.commandReturn)
        store.saveCommitAndSendShortcut(.commandShiftReturn)

        #expect(defaults.object(forKey: "panelScreen") as? String == "main")
        #expect(defaults.object(forKey: "autoShowMode") as? String == "allApps")
        #expect(defaults.object(forKey: "appTheme") as? String == "light")
        #expect(defaults.object(forKey: "panelFontName") as? String == "Menlo-Regular")
        #expect(defaults.object(forKey: "panelFontFamilyName") as? String == "Menlo")
        #expect(defaults.object(forKey: "autoShowApps") is Data)
        #expect(defaults.object(forKey: "hiddenPanelStatusItems") as? [String] == ["lineCount"])
        #expect(defaults.object(forKey: "commitShortcut") as? [Int] == PanelShortcut.commandReturn.storedValue)
        #expect(defaults.object(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)

        for key in ["panelFontSize", "panelOpacity", "panelDefaultWidth", "panelDefaultHeight"] {
            let number = try #require(defaults.object(forKey: key) as? NSNumber, "\(key)")
            #expect(CFGetTypeID(number) != CFBooleanGetTypeID(), "\(key)")
        }
        #expect(defaults.double(forKey: "panelFontSize") == 20)
        #expect(defaults.double(forKey: "panelOpacity") == 0.5)
        #expect(defaults.double(forKey: "panelDefaultWidth") == 700)
        #expect(defaults.double(forKey: "panelDefaultHeight") == 500)

        for key in ["hidesMenuBarIcon", "hasShownFirstLaunchTutorial"] {
            let flag = try #require(defaults.object(forKey: key) as? NSNumber, "\(key)")
            #expect(CFGetTypeID(flag) == CFBooleanGetTypeID(), "\(key)")
        }
    }

    @Test("AC-2: フォント名・ファミリー名は nil か空の文字列を保存するとキーが消える")
    func emptyFontNamesRemoveKeys() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults

        let store = SettingsStore(defaults: defaults)
        store.savePanelFontName("Menlo-Regular")
        store.savePanelFontFamilyName("Menlo")
        store.savePanelFontName(nil)
        store.savePanelFontFamilyName("")

        #expect(defaults.object(forKey: "panelFontName") == nil)
        #expect(defaults.object(forKey: "panelFontFamilyName") == nil)
        #expect(store.loadPanelFontName() == nil)
        #expect(store.loadPanelFontFamilyName() == nil)
    }

    @Test("AC-2: 型の違う値・知らない値・空の文字列を直接入れると、列挙・文字列・真偽値は初期値になる")
    func unreadableValuesFallBackToDefaults() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        let enumKeys = ["panelScreen", "autoShowMode", "appTheme"]
        let badEnumValues: [Any] = ["bogus", "", 5, true, ["main"]]
        for value in badEnumValues {
            for key in enumKeys {
                defaults.set(value, forKey: key)
            }
            #expect(store.loadPanelScreen() == .nearFocusedField, "\(value)")
            #expect(store.loadAutoShowMode() == .off, "\(value)")
            #expect(store.loadAppTheme() == .system, "\(value)")
        }

        let badNameValues: [Any] = ["", 5, true, ["Menlo"]]
        for value in badNameValues {
            defaults.set(value, forKey: "panelFontName")
            defaults.set(value, forKey: "panelFontFamilyName")
            #expect(store.loadPanelFontName() == nil, "\(value)")
            #expect(store.loadPanelFontFamilyName() == nil, "\(value)")
        }

        let badFlagValues: [Any] = ["yes", 1, ["true"]]
        for value in badFlagValues {
            defaults.set(value, forKey: "hidesMenuBarIcon")
            defaults.set(value, forKey: "hasShownFirstLaunchTutorial")
            #expect(!store.loadHidesMenuBarIcon(), "\(value)")
            #expect(!store.loadHasShownFirstLaunchTutorial(), "\(value)")
        }
    }

    @Test("AC-2: 数値でない値は文字サイズ・透明度・既定の大きさの初期値になり、範囲外の文字サイズ・透明度は端に収まる")
    func numericValuesFallBackOrClamp() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        let nonNumbers: [Any] = ["abc", true, [20]]
        for value in nonNumbers {
            for key in ["panelFontSize", "panelOpacity", "panelDefaultWidth", "panelDefaultHeight"] {
                defaults.set(value, forKey: key)
            }
            #expect(store.loadPanelFontSize() == 14, "\(value)")
            #expect(store.loadPanelOpacity() == 1.0, "\(value)")
            #expect(store.loadPanelDefaultWidth() == 520, "\(value)")
            #expect(store.loadPanelDefaultHeight() == 340, "\(value)")
        }

        defaults.set(100.0, forKey: "panelFontSize")
        #expect(store.loadPanelFontSize() == 32)
        defaults.set(1.0, forKey: "panelFontSize")
        #expect(store.loadPanelFontSize() == 10)
        defaults.set(5.0, forKey: "panelOpacity")
        #expect(store.loadPanelOpacity() == 1.0)
        defaults.set(0.1, forKey: "panelOpacity")
        #expect(store.loadPanelOpacity() == 0.4)
    }

    @Test("AC-2: 既定の大きさが範囲外なら、端に収めずに初期値になる。保存するときは端に収める")
    func defaultSizeOutOfRangeUsesDefault() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        for value in [0.0, 319.0, 4001.0, 100_000.0] {
            defaults.set(value, forKey: "panelDefaultWidth")
            #expect(store.loadPanelDefaultWidth() == 520, "\(value)")
        }
        for value in [0.0, 159.0, 4001.0, 100_000.0] {
            defaults.set(value, forKey: "panelDefaultHeight")
            #expect(store.loadPanelDefaultHeight() == 340, "\(value)")
        }

        store.savePanelDefaultWidth(100_000)
        store.savePanelDefaultHeight(1)
        #expect(defaults.double(forKey: "panelDefaultWidth") == 4000)
        #expect(defaults.double(forKey: "panelDefaultHeight") == 160)
        store.savePanelFontSize(.nan)
        store.savePanelOpacity(-.infinity)
        #expect(defaults.double(forKey: "panelFontSize") == 14)
        #expect(defaults.double(forKey: "panelOpacity") == 1.0)
    }

    @Test("AC-3: 確定キー・確定+送信キーは、未保存なら既定のキーになる")
    func shortcutsWhenNothingStored() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let store = SettingsStore(defaults: temp.defaults)
        #expect(store.loadCommitShortcut() == PanelShortcut.defaultCommitKey)
        #expect(store.loadCommitAndSendShortcut() == PanelShortcut.defaultCommitAndSendKey)
    }

    @Test("AC-3: 新しい形の配列を読み、空の配列は未登録(nil)になる")
    func newFormatShortcuts() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        defaults.set(PanelShortcut.shiftReturn.storedValue, forKey: "commitShortcut")
        defaults.set(PanelShortcut.commandReturn.storedValue, forKey: "commitAndSendShortcut")
        #expect(store.loadCommitShortcut() == .shiftReturn)
        #expect(store.loadCommitAndSendShortcut() == .commandReturn)

        defaults.set([Int](), forKey: "commitShortcut")
        defaults.set([Int](), forKey: "commitAndSendShortcut")
        #expect(store.loadCommitShortcut() == nil)
        #expect(store.loadCommitAndSendShortcut() == nil)
    }

    @Test("AC-3: 配列でない値・読めない配列は既定のキーになる")
    func brokenNewFormatShortcuts() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        let nonArrays: [Any] = ["x", 3, true]
        for value in nonArrays {
            defaults.set(value, forKey: "commitShortcut")
            defaults.set(value, forKey: "commitAndSendShortcut")
            #expect(store.loadCommitShortcut() == PanelShortcut.defaultCommitKey, "\(value)")
            #expect(store.loadCommitAndSendShortcut() == PanelShortcut.defaultCommitAndSendKey, "\(value)")
        }

        let unreadableArrays: [[Any]] = [[1, 2, 3], [36, 0], ["a", "b"], [true, false], [-1, 1_048_576]]
        for value in unreadableArrays {
            defaults.set(value, forKey: "commitShortcut")
            defaults.set(value, forKey: "commitAndSendShortcut")
            #expect(store.loadCommitShortcut() == PanelShortcut.defaultCommitKey, "\(value)")
            #expect(store.loadCommitAndSendShortcut() == PanelShortcut.defaultCommitAndSendKey, "\(value)")
        }
    }

    @Test("AC-3: 古い形の文字列を読み、知らない値は古い形の既定のキーになる")
    func legacyFormatShortcuts() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        defaults.set("shiftEnter", forKey: "commitKey")
        defaults.set("commandShiftEnter", forKey: "commitAndSendKey")
        #expect(store.loadCommitShortcut() == .shiftReturn)
        #expect(store.loadCommitAndSendShortcut() == .commandShiftReturn)

        defaults.set("none", forKey: "commitKey")
        defaults.set("none", forKey: "commitAndSendKey")
        #expect(store.loadCommitShortcut() == nil)
        #expect(store.loadCommitAndSendShortcut() == nil)

        defaults.set("bogus", forKey: "commitKey")
        defaults.set("bogus", forKey: "commitAndSendKey")
        #expect(store.loadCommitShortcut() == PanelShortcut.legacyDefaultCommitKey)
        #expect(store.loadCommitAndSendShortcut() == PanelShortcut.legacyDefaultCommitAndSendKey)
    }

    @Test("AC-3: 古い形のキーが片方だけ保存されていると、もう片方は古い形の既定のキーになり、新しい形が壊れていても同じになる")
    func partialLegacyShortcuts() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        defaults.set("commandEnter", forKey: "commitKey")
        #expect(store.loadCommitShortcut() == .commandReturn)
        #expect(store.loadCommitAndSendShortcut() == PanelShortcut.legacyDefaultCommitAndSendKey)

        defaults.set("x", forKey: "commitShortcut")
        defaults.set([1, 2, 3], forKey: "commitAndSendShortcut")
        #expect(store.loadCommitShortcut() == PanelShortcut.legacyDefaultCommitKey)
        #expect(store.loadCommitAndSendShortcut() == PanelShortcut.legacyDefaultCommitAndSendKey)
    }

    @Test("AC-3: 新しい形が保存されていれば、古い形より優先して読む")
    func newFormatTakesPrecedenceOverLegacy() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let defaults = temp.defaults
        let store = SettingsStore(defaults: defaults)

        defaults.set("shiftEnter", forKey: "commitKey")
        defaults.set(PanelShortcut.commandShiftReturn.storedValue, forKey: "commitShortcut")
        #expect(store.loadCommitShortcut() == .commandShiftReturn)

        defaults.set([Int](), forKey: "commitAndSendShortcut")
        defaults.set("commandEnter", forKey: "commitAndSendKey")
        #expect(store.loadCommitAndSendShortcut() == nil)
    }
}
