import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsURLFoldTests {
    private func withDefaults(_ body: (SettingsStore, InMemoryDefaults) throws -> Void) throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        try body(SettingsStore(defaults: temp.defaults), temp.defaults)
    }

    @Test("AC-14: キーが無い利用者は、URL を畳む設定がオンになる")
    func missingKeyIsOn() throws {
        try withDefaults { store, defaults in
            #expect(defaults.object(forKey: "editorFoldsURLs") == nil)
            #expect(AppSettings(store: store).editorFoldsURLs == true)
            #expect(store.value(SettingDefinitions.editorFoldsURLs) == true)
        }
    }

    @Test("AC-14: 真偽値でない保存値は読めず、オンになる")
    func unreadableValuesAreOn() throws {
        try withDefaults { store, defaults in
            for unreadable: Any in [1, 0, "YES", "false", ""] {
                defaults.set(unreadable, forKey: "editorFoldsURLs")
                #expect(AppSettings(store: store).editorFoldsURLs == true, "\(unreadable)")
            }
        }
    }

    @Test("AC-15: URL を畳む設定を変えるとその場で保存され、設定を作り直しても残る")
    func changedValueIsSavedAndSurvivesRecreation() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)

            settings.editorFoldsURLs = false
            #expect(defaults.object(forKey: "editorFoldsURLs") as? Bool == false)
            #expect(AppSettings(store: store).editorFoldsURLs == false)

            settings.editorFoldsURLs = true
            #expect(defaults.object(forKey: "editorFoldsURLs") as? Bool == true)
            #expect(AppSettings(store: store).editorFoldsURLs == true)
        }
    }
}
