import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct EditorSettingsModelTests {
    /// @note p0-822
    private func makeSettings(suite name: String) throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: name))
        return AppSettings(store: SettingsStore(defaults: defaults))
    }

    private func removeSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    // MARK: - フォントの名前の表示

    private func savedSettings(suite name: String, fontName: String?, familyName: String?) throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: name))
        let store = SettingsStore(defaults: defaults)
        store.savePanelFontName(fontName)
        store.savePanelFontFamilyName(familyName)
        return AppSettings(store: store)
    }

    @Test("AC-2: 何も選んでいなければ名前の表示は「システムフォント」で、書体を選ぶとその表示名になり、押せる状態になる")
    func fontDisplayNameFollowsSelection() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(model.fontDisplayName == String(localized: "システムフォント"))
        #expect(model.isSystemFont)

        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 14))
        settings.selectPanelFont(menlo)
        #expect(model.fontDisplayName == menlo.displayName)
        #expect(!model.isSystemFont)

        let hiragino = try #require(NSFont(name: "HiraginoSans-W6", size: 14))
        settings.selectPanelFont(hiragino)
        #expect(model.fontDisplayName == hiragino.displayName)
        #expect(model.fontDisplayName != menlo.displayName)
        #expect(!model.isSystemFont)
    }

    @Test("AC-2: 起動し直しても、選んだ書体の表示名が出て押せる状態になる")
    func fontDisplayNameSurvivesRecreation() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 14))
        settings.selectPanelFont(menlo)

        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite))
        #expect(relaunched.fontDisplayName == menlo.displayName)
        #expect(!relaunched.isSystemFont)
    }

    @Test("AC-6: システムフォントに戻すと、保存された書体名・ファミリー名が消えて名前の表示が「システムフォント」になり、文字サイズは変わらない")
    func resetFontToSystemClearsFont() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 20))
        settings.selectPanelFont(menlo)
        #expect(!model.isSystemFont)

        model.resetFontToSystem()

        #expect(model.fontDisplayName == String(localized: "システムフォント"))
        #expect(model.isSystemFont)
        #expect(settings.panelFontName == nil)
        #expect(settings.panelFontFamilyName == nil)
        #expect(settings.panelFontSize == 20)
        #expect(settings.panelFont.fontName == NSFont.systemFont(ofSize: 20).fontName)

        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(defaults.object(forKey: "panelFontName") == nil)
        #expect(defaults.object(forKey: "panelFontFamilyName") == nil)
    }

    @Test("AC-8: 保存された書体が Mac に無く同じファミリーがあるときは、ファミリーの標準の太さで表示し、名前の表示もそれになり、保存された値は書き換えない")
    func missingFaceFallsBackToFamilyRegular() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try savedSettings(
            suite: suite,
            fontName: "Menlo-TatakiNoteNoSuchFace",
            familyName: "Menlo"
        )
        let model = EditorSettingsModel(settings: settings)
        let regular = try #require(NSFont(name: "Menlo-Regular", size: 14))

        #expect(model.fontDisplayName == regular.displayName)
        #expect(!model.isSystemFont)
        #expect(settings.panelFont.fontName == "Menlo-Regular")

        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(defaults.string(forKey: "panelFontName") == "Menlo-TatakiNoteNoSuchFace")
        #expect(defaults.string(forKey: "panelFontFamilyName") == "Menlo")
    }

    @Test("AC-9: 保存された書体もファミリーも Mac に無いときは、システムフォントで表示し、名前の表示も「システムフォント」になり、保存された値は書き換えない")
    func missingFamilyFallsBackToSystemFont() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try savedSettings(
            suite: suite,
            fontName: "TatakiNoteNoSuchFont-Regular",
            familyName: "TatakiNoteNoSuchFamily"
        )
        let model = EditorSettingsModel(settings: settings)

        #expect(model.fontDisplayName == String(localized: "システムフォント"))
        #expect(model.isSystemFont)
        #expect(settings.panelFont.fontName == NSFont.systemFont(ofSize: settings.panelFontSize).fontName)

        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(defaults.string(forKey: "panelFontName") == "TatakiNoteNoSuchFont-Regular")
        #expect(defaults.string(forKey: "panelFontFamilyName") == "TatakiNoteNoSuchFamily")
    }

    // MARK: - 文字サイズ・透明度

    @Test("AC-4: 文字サイズは初期値が「14 pt」で、変えると pt で表示され、起動し直しても残る")
    func fontSizeText() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(model.fontSizeText == "14 pt")
        settings.panelFontSize = 15
        #expect(model.fontSizeText == "15 pt")
        settings.panelFontSize = 10
        #expect(model.fontSizeText == "10 pt")
        settings.panelFontSize = 32
        #expect(model.fontSizeText == "32 pt")

        settings.panelFontSize = 15
        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite))
        #expect(relaunched.fontSizeText == "15 pt")
    }

    @Test("AC-5: 透明度は初期値が「100%」で、変えると % で表示され(四捨五入)、起動し直しても残る")
    func opacityPercentText() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(model.opacityPercentText == "100%")
        settings.panelOpacity = 0.7
        #expect(model.opacityPercentText == "70%")
        settings.panelOpacity = 0.85
        #expect(model.opacityPercentText == "85%")
        settings.panelOpacity = 0.4
        #expect(model.opacityPercentText == "40%")
        settings.panelOpacity = 0.456
        #expect(model.opacityPercentText == "46%")

        settings.panelOpacity = 0.7
        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite))
        #expect(relaunched.opacityPercentText == "70%")
    }

    // MARK: - 帯の項目

    @Test("AC-6: 帯の6項目は初期はすべて表示で、1つずつ切り替えられ、切り替えた値は起動し直しても残る")
    func statusItemVisibility() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(PanelStatusItem.allCases.count == 6)
        for item in PanelStatusItem.allCases {
            #expect(model.isStatusItemVisible(item), "\(item)")
        }

        model.setStatusItem(.characterCount, isVisible: false)
        #expect(!model.isStatusItemVisible(.characterCount))
        #expect(model.isStatusItemVisible(.lineCount))
        #expect(settings.hiddenPanelStatusItems == [.characterCount])

        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite))
        #expect(!relaunched.isStatusItemVisible(.characterCount))
        #expect(relaunched.isStatusItemVisible(.close))

        relaunched.setStatusItem(.characterCount, isVisible: true)
        #expect(relaunched.isStatusItemVisible(.characterCount))
    }

    @Test("AC-9: 確定キー・確定+送信キーが登録なし(nil)のときだけ、その項目に「帯に出ない」ことを添える")
    func statusItemNoteForUnassignedKeys() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        // @note p0-833
        #expect(model.statusItemNote(.commit) == .keyNotAssigned)
        #expect(model.statusItemNote(.commitAndSend) == nil)
        for item in [PanelStatusItem.lineBreak, .close, .characterCount, .lineCount] {
            #expect(model.statusItemNote(item) == nil, "\(item)")
        }

        settings.commitKey = .commandShiftReturn
        #expect(model.statusItemNote(.commit) == nil)

        settings.commitAndSendKey = nil
        #expect(model.statusItemNote(.commitAndSend) == .keyNotAssigned)

        // @note p0-834
        model.setStatusItem(.commitAndSend, isVisible: false)
        #expect(model.statusItemNote(.commitAndSend) == .keyNotAssigned)
    }
}
