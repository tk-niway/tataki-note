import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct EditorSettingsModelTests {
    /// @note p0-820
    private func member(_ postScriptName: String, weight: Int, italic: Bool = false) -> [Any] {
        let traits: NSFontTraitMask = italic ? .italicFontMask : []
        return [postScriptName, "Face", NSNumber(value: weight), NSNumber(value: traits.rawValue)]
    }

    /// @note p0-821
    private func makeChoices(_ members: [String: [[Any]]?], families: [String]? = nil) -> [FontChoice] {
        FontChoices.make(
            families: families ?? members.keys.sorted(),
            members: { family in members[family] ?? nil },
            localizedName: { "表示:\($0)" }
        )
    }

    /// @note p0-822
    private func makeSettings(suite name: String) throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: name))
        return AppSettings(store: SettingsStore(defaults: defaults))
    }

    private func removeSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    // MARK: - フォントの選択肢

    @Test("AC-2: 選択肢は先頭がシステムフォントで、ファミリーごとに1つ、表示名(localizedName の値)の順に並ぶ")
    func choicesStartWithSystemAndSortByDisplayName() {
        let choices = FontChoices.make(
            families: ["Zeta", "Alpha", "Beta"],
            members: { [self.member("\($0)-Regular", weight: 5)] },
            // @note p0-823
            localizedName: { ["Zeta": "Aardvark", "Alpha": "Mango", "Beta": "Zebra"][$0] ?? $0 }
        )

        #expect(choices.first == FontChoice.system)
        #expect(choices.first?.id == FontChoice.systemID)
        #expect(choices.first?.familyName == nil)
        #expect(choices.first?.postScriptName == nil)
        #expect(choices.first?.displayName == String(localized: "システムフォント"))
        #expect(choices.dropFirst().map(\.displayName) == ["Aardvark", "Mango", "Zebra"])
        #expect(choices.dropFirst().map(\.familyName) == ["Zeta", "Alpha", "Beta"])
        #expect(Set(choices.map(\.id)).count == choices.count)
    }

    @Test("AC-2: 代表は斜体でない太さ 5 のメンバー。太さ 5 が無ければ 5 に最も近いもの(同じ近さなら細い方)、斜体でないものが無ければ最初のもの")
    func representativeIsRegularWeight() {
        let choices = makeChoices([
            "Regular": [
                member("Regular-Italic", weight: 5, italic: true),
                member("Regular-Light", weight: 3),
                member("Regular-Regular", weight: 5),
                member("Regular-Bold", weight: 9),
            ],
            // @note p0-824
            "ThreeSeven": [member("ThreeSeven-Bold", weight: 7), member("ThreeSeven-Light", weight: 3)],
            // @note p0-825
            "Steps": [0, 1, 2, 3, 4, 6, 7, 8, 9].map { member("Steps-W\($0)", weight: $0) },
            // @note p0-826
            "ItalicOnly": [member("ItalicOnly-BoldItalic", weight: 9, italic: true), member("ItalicOnly-Italic", weight: 5, italic: true)],
            // @note p0-827
            "NoTraits": [member("NoTraits-Light", weight: 3), ["NoTraits-Plain"]],
        ])
        var postScriptNames: [String: String] = [:]
        for choice in choices {
            if let familyName = choice.familyName {
                postScriptNames[familyName] = choice.postScriptName
            }
        }
        #expect(postScriptNames.count == 5)

        #expect(postScriptNames["Regular"] == "Regular-Regular")
        #expect(postScriptNames["ThreeSeven"] == "ThreeSeven-Light")
        #expect(postScriptNames["Steps"] == "Steps-W4")
        #expect(postScriptNames["ItalicOnly"] == "ItalicOnly-BoldItalic")
        #expect(postScriptNames["NoTraits"] == "NoTraits-Plain")
    }

    @Test("AC-2: メンバーが取れない・空・形の合わないファミリーは飛ばし、表示名は localizedName の値")
    func skipsFamiliesWithoutUsableMembers() {
        let choices = makeChoices([
            "Usable": [member("Usable-Regular", weight: 5)],
            "Empty": [],
            "NilMembers": nil,
            // @note p0-828
            "Malformed": [[NSNumber(value: 1), "Face", NSNumber(value: 5), NSNumber(value: 0)], ["", "Face"]],
        ])

        #expect(choices.map(\.familyName) == [nil, "Usable"])
        #expect(choices.last?.displayName == "表示:Usable")
        #expect(choices.last?.postScriptName == "Usable-Regular")
    }

    @Test("AC-2: システムフォントの内部名(先頭が .)のファミリーは選択肢に出ず、PostScript 名が . で始まるメンバーは代表に選ばれない")
    func skipsSystemFontInternalNames() {
        let choices = makeChoices([
            ".AppleSystemUIFont": [member(".SFNS-Regular", weight: 5)],
            "Foo": [member(".Foo-Hidden", weight: 5), member("Foo-Light", weight: 3)],
            "AllHidden": [member(".AllHidden-Regular", weight: 5), member(".AllHidden-Bold", weight: 9)],
        ])

        #expect(choices.map(\.familyName) == [nil, "Foo"])
        #expect(choices.last?.postScriptName == "Foo-Light")
        #expect(!choices.contains { $0.familyName?.hasPrefix(".") == true || $0.postScriptName?.hasPrefix(".") == true })
    }

    @Test("AC-2: Mac に入っている一覧には、ヒラギノ角ゴシック(日本語)と Menlo(等幅)があり、先頭が . の選択肢は無い")
    func systemChoicesIncludeJapaneseAndMonospacedFonts() throws {
        let choices = FontChoices.systemChoices()

        #expect(choices.first == FontChoice.system)
        let hiragino = try #require(choices.first { $0.familyName == "Hiragino Sans" })
        let menlo = try #require(choices.first { $0.familyName == "Menlo" })
        #expect(menlo.postScriptName == "Menlo-Regular")
        // @note p0-829
        #expect(hiragino.postScriptName != "HiraginoSans-W0")
        let hiraginoName = try #require(hiragino.postScriptName)
        #expect(NSFont(name: hiraginoName, size: 14)?.familyName == "Hiragino Sans")
        #expect(!choices.contains { $0.familyName?.hasPrefix(".") == true || $0.postScriptName?.hasPrefix(".") == true })
    }

    @Test("AC-2: 何も選んでいなければシステムフォントが選ばれている")
    func systemFontIsSelectedByDefault() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let model = EditorSettingsModel(settings: try makeSettings(suite: suite))

        #expect(model.selectedFontChoiceID == FontChoice.systemID)
        #expect(model.systemFontChoice == FontChoice.system)
        #expect(model.familyFontChoices.count == model.fontChoices.count - 1)
    }

    // MARK: - 選んでいるフォント

    @Test("AC-3: フォントを選ぶとそのファミリーの標準の太さの名前が保存され、起動し直しても同じフォントが選ばれている。システムを選ぶと nil")
    func selectingFontSavesAndRestores() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)
        let menlo = try #require(model.fontChoices.first { $0.familyName == "Menlo" })

        model.selectedFontChoiceID = menlo.id
        #expect(settings.panelFontName == "Menlo-Regular")
        #expect(model.selectedFontChoiceID == menlo.id)

        // @note p0-830
        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite))
        #expect(relaunched.selectedFontChoiceID == menlo.id)

        relaunched.selectedFontChoiceID = FontChoice.systemID
        #expect(try makeSettings(suite: suite).panelFontName == nil)
        #expect(relaunched.selectedFontChoiceID == FontChoice.systemID)
    }

    @Test("AC-3: 保存されたフォントが Mac に無いとき・システムフォントの内部名(先頭が .)のときは、システムフォントが選ばれた表示になる")
    func missingOrInternalFontShowsSystem() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        settings.panelFontName = "TatakiNoteNoSuchFont-Regular"
        #expect(model.selectedFontChoiceID == FontChoice.systemID)

        // @note p0-831
        settings.panelFontName = ".AppleSystemUIFont"
        #expect(model.selectedFontChoiceID == FontChoice.systemID)
    }

    @Test("AC-3: 別の太さが保存されていても同じファミリーが選ばれた表示になり、同じ項目を選び直しても保存された名前は書き換えない")
    func otherWeightShowsSameFamily() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)
        let hiragino = try #require(model.fontChoices.first { $0.familyName == "Hiragino Sans" })

        settings.panelFontName = "HiraginoSans-W6"
        #expect(model.selectedFontChoiceID == hiragino.id)
        model.selectedFontChoiceID = hiragino.id
        #expect(settings.panelFontName == "HiraginoSans-W6")

        // @note p0-832
        settings.panelFontName = "TatakiNoteNoSuchFont-Regular"
        model.selectedFontChoiceID = FontChoice.systemID
        #expect(settings.panelFontName == "TatakiNoteNoSuchFont-Regular")
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
        let model = EditorSettingsModel(settings: settings, fontChoices: [.system])

        #expect(model.fontSizeText == "14 pt")
        settings.panelFontSize = 15
        #expect(model.fontSizeText == "15 pt")
        settings.panelFontSize = 10
        #expect(model.fontSizeText == "10 pt")
        settings.panelFontSize = 32
        #expect(model.fontSizeText == "32 pt")

        settings.panelFontSize = 15
        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite), fontChoices: [.system])
        #expect(relaunched.fontSizeText == "15 pt")
    }

    @Test("AC-5: 透明度は初期値が「100%」で、変えると % で表示され(四捨五入)、起動し直しても残る")
    func opacityPercentText() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings, fontChoices: [.system])

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
        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite), fontChoices: [.system])
        #expect(relaunched.opacityPercentText == "70%")
    }

    // MARK: - 帯の項目

    @Test("AC-6: 帯の6項目は初期はすべて表示で、1つずつ切り替えられ、切り替えた値は起動し直しても残る")
    func statusItemVisibility() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings, fontChoices: [.system])

        #expect(PanelStatusItem.allCases.count == 6)
        for item in PanelStatusItem.allCases {
            #expect(model.isStatusItemVisible(item), "\(item)")
        }

        model.setStatusItem(.characterCount, isVisible: false)
        #expect(!model.isStatusItemVisible(.characterCount))
        #expect(model.isStatusItemVisible(.lineCount))
        #expect(settings.hiddenPanelStatusItems == [.characterCount])

        let relaunched = EditorSettingsModel(settings: try makeSettings(suite: suite), fontChoices: [.system])
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
        let model = EditorSettingsModel(settings: settings, fontChoices: [.system])

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
