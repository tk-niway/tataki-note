import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsBottomPaddingTests {
    private func withDefaults(_ body: (SettingsStore, InMemoryDefaults) throws -> Void) throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        try body(SettingsStore(defaults: temp.defaults), temp.defaults)
    }

    @Test("AC-18: キーが無い前の版の利用者は、余白が 3 行になる")
    func missingKeyIsDefault() throws {
        try withDefaults { store, defaults in
            #expect(defaults.object(forKey: "editorBottomPaddingLines") == nil)
            #expect(AppSettings(store: store).editorBottomPaddingLines == 3)
        }
    }

    @Test("AC-18: 変えた余白の行数は、設定を作り直しても残り、範囲外は丸めて保存する")
    func savedLinesSurviveRecreation() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)

            settings.editorBottomPaddingLines = 8
            #expect(AppSettings(store: store).editorBottomPaddingLines == 8)
            #expect(defaults.object(forKey: "editorBottomPaddingLines") as? Int == 8)

            settings.editorBottomPaddingLines = 0
            #expect(AppSettings(store: store).editorBottomPaddingLines == 0)

            settings.editorBottomPaddingLines = 99
            #expect(settings.editorBottomPaddingLines == 20)
            #expect(AppSettings(store: store).editorBottomPaddingLines == 20)

            settings.editorBottomPaddingLines = -4
            #expect(settings.editorBottomPaddingLines == 0)
            #expect(AppSettings(store: store).editorBottomPaddingLines == 0)
        }
    }

    @Test("AC-18: 保存してある値が範囲外・数でないときは、範囲の端か初期値になる")
    func storedValuesAreClampedOrFallBack() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Int)] = [
                (-1, 0),
                (21, 20),
                (1e30, 20),
                (-1e30, 0),
                (5.9, 5),
                (Double.infinity, 3),
                (Double.nan, 3),
                ("5", 3),
                (true, 3),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorBottomPaddingLines")
                #expect(store.value(SettingDefinitions.editorBottomPaddingLines) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorBottomPaddingLines == expected, "\(stored)")
            }
        }
    }
}
