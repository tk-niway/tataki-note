import AppKit
import Observation
import os
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsDerivedValuesTests {
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppSettings(store: SettingsStore(defaults: defaults)), defaults)
    }

    private func expectedFont(_ settings: AppSettings) -> NSFont {
        PanelTextStyle.font(
            name: settings.panelFontName,
            familyName: settings.panelFontFamilyName,
            size: settings.panelFontSize
        )
    }

    // MARK: - フォント(AC-13)

    @Test("AC-13: panelFont は、設定を変えない間は同じインスタンスを返す")
    func panelFontIsStableWhileSettingsUnchanged() throws {
        try withSettings { settings, _ in
            let first = settings.panelFont
            #expect(settings.panelFont === first)
            settings.commitKey = .commandReturn
            settings.panelOpacity = 0.5
            #expect(settings.panelFont === first)
        }
    }

    @Test("AC-13: 文字サイズ・名前・ファミリー名を変えると、直後の panelFont が新しい設定のフォントになる")
    func panelFontFollowsEachSetting() throws {
        try withSettings { settings, _ in
            let initial = settings.panelFont

            settings.panelFontSize = 20
            #expect(settings.panelFont !== initial)
            #expect(settings.panelFont.pointSize == 20)
            #expect(settings.panelFont == expectedFont(settings))

            let menlo = try #require(NSFont(name: "Menlo-Regular", size: 14))
            settings.panelFontName = menlo.fontName
            #expect(settings.panelFont.fontName == menlo.fontName)
            #expect(settings.panelFont == expectedFont(settings))

            let beforeFamily = settings.panelFont
            settings.panelFontName = nil
            #expect(settings.panelFont !== beforeFamily)
            #expect(settings.panelFont == expectedFont(settings))
        }
    }

    @Test("AC-13: 範囲外の文字サイズや空の名前を入れても、panelFont は丸めた後の設定のフォントになる")
    func panelFontUsesNormalizedValues() throws {
        try withSettings { settings, _ in
            settings.panelFontSize = 100_000
            #expect(settings.panelFontSize == PanelTextStyle.clampedFontSize(100_000))
            #expect(settings.panelFont.pointSize == CGFloat(settings.panelFontSize))

            settings.panelFontName = ""
            #expect(settings.panelFontName == nil)
            #expect(settings.panelFont == expectedFont(settings))
        }
    }

    @Test("AC-13: selectPanelFont と resetPanelFontToSystem の直後も、新しい設定のフォントになる")
    func panelFontFollowsSelectAndReset() throws {
        try withSettings { settings, _ in
            let menlo = try #require(NSFont(name: "Menlo-Regular", size: 18))
            settings.selectPanelFont(menlo)
            #expect(settings.panelFont.fontName == menlo.fontName)
            #expect(settings.panelFont.pointSize == 18)
            #expect(settings.panelFont == expectedFont(settings))

            settings.resetPanelFontToSystem()
            #expect(settings.panelFontName == nil)
            #expect(settings.panelFont.pointSize == 18)
            #expect(settings.panelFont == expectedFont(settings))
            #expect(settings.panelFont.fontName != menlo.fontName)
        }
    }

    @Test("AC-13: 保存した設定で作り直した AppSettings でも、同じフォントになる")
    func panelFontSurvivesRecreation() throws {
        try withSettings { settings, defaults in
            let menlo = try #require(NSFont(name: "Menlo-Regular", size: 16))
            settings.selectPanelFont(menlo)

            let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
            #expect(reloaded.panelFont == settings.panelFont)
            #expect(reloaded.panelFont == expectedFont(reloaded))
            #expect(reloaded.panelFont.fontName == menlo.fontName)
            #expect(reloaded.panelFont.pointSize == 16)
        }
    }

    @Test("AC-13: panelFont の変化は観測できる")
    func panelFontChangeIsObservable() throws {
        try withSettings { settings, _ in
            let changes = OSAllocatedUnfairLock(initialState: 0)
            withObservationTracking {
                _ = settings.panelFont
            } onChange: {
                changes.withLock { $0 += 1 }
            }
            settings.panelFontSize = 22
            #expect(changes.withLock { $0 } == 1)
        }
    }

    // MARK: - キーの表示文字(AC-14)

    @Test("AC-14: 帯のキーの表示文字は、設定したキーの表示文字になる")
    func keyDisplayTextsMatchKeys() throws {
        try withSettings { settings, _ in
            #expect(settings.commitKeyDisplayText == PanelShortcut.commandShiftReturn.displayText)
            #expect(settings.commitAndSendKeyDisplayText == PanelShortcut.commandReturn.displayText)
            #expect(settings.commitKeyDisplayText == "⇧⌘↩")
            #expect(settings.commitAndSendKeyDisplayText == "⌘↩")
        }
    }

    @Test("AC-14: キーを変えるとすぐ表示文字が変わり、登録を消すと nil になる")
    func keyDisplayTextsFollowKeyChanges() throws {
        try withSettings { settings, _ in
            let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
            settings.commitKey = commandK
            #expect(settings.commitKeyDisplayText == commandK.displayText)
            #expect(settings.commitKeyDisplayText == "⌘K")

            settings.commitAndSendKey = .shiftReturn
            #expect(settings.commitAndSendKeyDisplayText == PanelShortcut.shiftReturn.displayText)

            settings.commitKey = nil
            #expect(settings.commitKeyDisplayText == nil)
            settings.commitAndSendKey = nil
            #expect(settings.commitAndSendKeyDisplayText == nil)
        }
    }

    @Test("AC-14: selectCommitKey・selectCommitAndSendKey で変えても、表示文字が変わる")
    func keyDisplayTextsFollowSelect() throws {
        try withSettings { settings, _ in
            #expect(settings.selectCommitKey(.shiftReturn))
            #expect(settings.commitKeyDisplayText == PanelShortcut.shiftReturn.displayText)
            #expect(settings.selectCommitAndSendKey(.commandShiftReturn))
            #expect(settings.commitAndSendKeyDisplayText == PanelShortcut.commandShiftReturn.displayText)
        }
    }

    @Test("AC-14: 保存した設定で作り直した AppSettings でも、同じ表示文字になる")
    func keyDisplayTextsSurviveRecreation() throws {
        try withSettings { settings, defaults in
            settings.commitKey = PanelShortcut(keyCode: 40, modifiers: [.command])
            settings.commitAndSendKey = nil

            let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
            #expect(reloaded.commitKeyDisplayText == settings.commitKeyDisplayText)
            #expect(reloaded.commitAndSendKeyDisplayText == nil)
        }
    }

    @Test("AC-14: refreshKeyDisplayTexts() を呼んでも、キーが同じなら値は変わらず、変化の通知も出ない")
    func refreshKeyDisplayTextsKeepsValuesAndDoesNotNotify() throws {
        try withSettings { settings, _ in
            let commit = settings.commitKeyDisplayText
            let commitAndSend = settings.commitAndSendKeyDisplayText

            let changes = OSAllocatedUnfairLock(initialState: 0)
            withObservationTracking {
                _ = settings.commitKeyDisplayText
                _ = settings.commitAndSendKeyDisplayText
            } onChange: {
                changes.withLock { $0 += 1 }
            }
            settings.refreshKeyDisplayTexts()

            #expect(settings.commitKeyDisplayText == commit)
            #expect(settings.commitAndSendKeyDisplayText == commitAndSend)
            #expect(changes.withLock { $0 } == 0)
        }
    }
}
