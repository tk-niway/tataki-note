import AppKit
import Testing
@testable import TatakiNote

@MainActor
@Suite(.serialized)
struct FontPanelControllerTests {
    private func makeSettings(suite name: String) throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: name))
        return AppSettings(store: SettingsStore(defaults: defaults))
    }

    private func removeSuite(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        var attempts = 0
        while attempts < 40 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
    }

    @Test("AC-3: フォントパネルで選んだ書体の名前・ファミリー名が設定に入り、起動し直しても同じ書体になる")
    func applyingFontSavesFaceAndFamily() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let controller = FontPanelController(settings: settings)
        let hiragino = try #require(NSFont(name: "HiraginoSans-W6", size: 20))

        controller.apply { _ in hiragino }

        #expect(settings.panelFontName == "HiraginoSans-W6")
        #expect(settings.panelFontFamilyName == "Hiragino Sans")
        let relaunched = try makeSettings(suite: suite)
        #expect(relaunched.panelFont.fontName == "HiraginoSans-W6")
    }

    @Test("AC-4: フォントパネルで変えたサイズは四捨五入して「文字サイズ」に入り、10〜32 に収まる")
    func applyingFontSizeRoundsAndClamps() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let controller = FontPanelController(settings: settings)
        let hiragino = try #require(NSFont(name: "HiraginoSans-W6", size: 40))

        controller.apply { _ in hiragino }
        #expect(settings.panelFontSize == 32)

        controller.apply { _ in NSFont.systemFont(ofSize: 15.6) }
        #expect(settings.panelFontSize == 16)

        controller.apply { _ in NSFont.systemFont(ofSize: 9) }
        #expect(settings.panelFontSize == 10)
    }

    @Test("AC-5: システムフォントのままサイズだけを変えると、フォント名・ファミリー名は無いまま文字サイズだけが変わる")
    func applyingSizeOnlyKeepsSystemFont() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let controller = FontPanelController(settings: settings)

        controller.apply { _ in NSFont.systemFont(ofSize: 18) }

        #expect(settings.panelFontName == nil)
        #expect(settings.panelFontFamilyName == nil)
        #expect(settings.panelFontSize == 18)
        let defaults = try #require(UserDefaults(suiteName: suite))
        #expect(defaults.object(forKey: "panelFontName") == nil)
        #expect(defaults.object(forKey: "panelFontFamilyName") == nil)
    }

    @Test("AC-3, AC-4: 変換には今の設定のフォントが渡される")
    func applyPassesCurrentSettingsFont() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 22))
        settings.selectPanelFont(menlo)
        let controller = FontPanelController(settings: settings)

        var received: NSFont?
        controller.apply {
            received = $0
            return $0
        }

        #expect(received?.fontName == "Menlo-Regular")
        #expect(received?.pointSize == 22)
        #expect(settings.panelFontName == "Menlo-Regular")
    }

    @Test("AC-7: フォントパネルを開いている間に文字サイズを変えると、フォントパネルで選ばれているサイズも同じになる")
    func fontPanelFollowsFontSize() async throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let manager = NSFontManager.shared
        let controller = FontPanelController(settings: settings, fontManager: manager)
        defer { controller.close() }

        controller.activate()
        #expect(manager.selectedFont?.pointSize == 14)

        settings.panelFontSize = 24
        try await waitUntil { manager.selectedFont?.pointSize == 24 }
        #expect(manager.selectedFont?.pointSize == 24)

        settings.panelFontSize = 11
        try await waitUntil { manager.selectedFont?.pointSize == 11 }
        #expect(manager.selectedFont?.pointSize == 11)
    }

    @Test("AC-7: フォントパネルを開いている間にシステムフォントに戻すと、フォントパネルで選ばれている書体もシステムフォントになる")
    func fontPanelFollowsReset() async throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let menlo = try #require(NSFont(name: "Menlo-Regular", size: 18))
        settings.selectPanelFont(menlo)
        let manager = NSFontManager.shared
        let controller = FontPanelController(settings: settings, fontManager: manager)
        defer { controller.close() }

        controller.activate()
        #expect(manager.selectedFont?.fontName == "Menlo-Regular")
        #expect(manager.selectedFont?.pointSize == 18)

        settings.resetPanelFontToSystem()
        let systemName = NSFont.systemFont(ofSize: 18).fontName
        try await waitUntil { manager.selectedFont?.fontName == systemName }
        #expect(manager.selectedFont?.fontName == systemName)
        #expect(manager.selectedFont?.pointSize == 18)
    }

    @Test("AC-7: 何度 activate しても設定の変化の監視は続き、設定が変わるたびにフォントパネルの選択が追いつく")
    func repeatedActivateKeepsFollowing() async throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let manager = NSFontManager.shared
        let controller = FontPanelController(settings: settings, fontManager: manager)
        defer { controller.close() }

        controller.activate()
        controller.activate()
        #expect(controller.isObserving)

        settings.panelFontSize = 20
        try await waitUntil { manager.selectedFont?.pointSize == 20 }
        #expect(manager.selectedFont?.pointSize == 20)

        settings.panelFontSize = 21
        try await waitUntil { manager.selectedFont?.pointSize == 21 }
        #expect(manager.selectedFont?.pointSize == 21)
    }

    @Test("AC-11: close で送り先が外れ、その後の設定の変更ではフォントパネルの選択が変わらない")
    func closeDetachesTargetAndStopsFollowing() async throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let manager = NSFontManager.shared
        let controller = FontPanelController(settings: settings, fontManager: manager)
        defer { controller.close() }

        controller.activate()
        #expect(manager.target === controller)
        #expect(controller.isActive)

        controller.close()
        #expect(manager.target !== controller)
        #expect(!controller.isActive)

        settings.panelFontSize = 27
        try await waitUntil { !controller.isObserving }
        #expect(!controller.isObserving)
        #expect(manager.selectedFont?.pointSize == 14)
    }
}
