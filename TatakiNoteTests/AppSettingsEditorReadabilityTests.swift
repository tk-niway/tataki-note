import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsEditorReadabilityTests {
    private func withDefaults(_ body: (SettingsStore, InMemoryDefaults) throws -> Void) throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        try body(SettingsStore(defaults: temp.defaults), temp.defaults)
    }

    private static let keys = [
        "editorLineHeightMultiple",
        "editorParagraphSpacingLines",
        "editorLetterSpacingPercent",
        "editorIndentsWrappedLines",
        "editorCaretShape",
        "editorHighlightsCurrentLine",
    ]

    @Test("AC-1: 6つのキーが無い前の版の利用者は、初期値(行間 1.0 倍・段落の間隔 0.25 行・字間 7%)になる")
    func missingKeysAreDefaults() throws {
        try withDefaults { store, defaults in
            for key in Self.keys {
                #expect(defaults.object(forKey: key) == nil, "\(key)")
            }
            let settings = AppSettings(store: store)
            #expect(settings.editorLineHeightMultiple == 1.0)
            #expect(settings.editorParagraphSpacingLines == 0.25)
            #expect(settings.editorLetterSpacingPercent == 7)
            #expect(settings.editorIndentsWrappedLines == true)
            #expect(settings.editorCaretShape == .bar)
            #expect(settings.editorHighlightsCurrentLine == false)
            #expect(settings.editorReadability == EditorReadability.standard)
        }
    }

    @Test("AC-2: 変えた6つの項目は、その場で保存され、設定を作り直しても残る")
    func changedValuesAreSavedAndSurviveRecreation() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)

            settings.editorLineHeightMultiple = 1.5
            settings.editorParagraphSpacingLines = 0.5
            settings.editorLetterSpacingPercent = 8
            settings.editorIndentsWrappedLines = false
            settings.editorCaretShape = .block
            settings.editorHighlightsCurrentLine = true

            #expect(defaults.object(forKey: "editorLineHeightMultiple") as? Double == 1.5)
            #expect(defaults.object(forKey: "editorParagraphSpacingLines") as? Double == 0.5)
            #expect(defaults.object(forKey: "editorLetterSpacingPercent") as? Int == 8)
            #expect(defaults.object(forKey: "editorIndentsWrappedLines") as? Bool == false)
            #expect(defaults.object(forKey: "editorCaretShape") as? String == "block")
            #expect(defaults.object(forKey: "editorHighlightsCurrentLine") as? Bool == true)

            let recreated = AppSettings(store: store)
            #expect(recreated.editorReadability == EditorReadability(
                lineHeightMultiple: 1.5,
                paragraphSpacingLines: 0.5,
                letterSpacingPercent: 8,
                indentsWrappedLines: false,
                caretShape: .block,
                highlightsCurrentLine: true
            ))
            #expect(settings.editorReadability == recreated.editorReadability)
        }
    }

    @Test("AC-2: 字間・段落の間隔を 0 にした値は、初期値に戻らずに 0 のまま残る")
    func zeroValuesSurviveRecreation() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)
            settings.editorLetterSpacingPercent = 0
            settings.editorParagraphSpacingLines = 0

            #expect(defaults.object(forKey: "editorLetterSpacingPercent") as? Int == 0)
            #expect(defaults.object(forKey: "editorParagraphSpacingLines") as? Double == 0)

            let recreated = AppSettings(store: store)
            #expect(recreated.editorLetterSpacingPercent == 0)
            #expect(recreated.editorParagraphSpacingLines == 0)
        }
    }

    @Test("AC-2: 範囲の外や刻みに乗らない値を入れても、丸めて保存する")
    func assignedValuesAreNormalizedBeforeSaving() throws {
        try withDefaults { store, _ in
            let settings = AppSettings(store: store)

            settings.editorLineHeightMultiple = 5
            #expect(settings.editorLineHeightMultiple == 2.0)
            settings.editorParagraphSpacingLines = 0.3
            #expect(settings.editorParagraphSpacingLines == 0.25)
            settings.editorLetterSpacingPercent = 99
            #expect(settings.editorLetterSpacingPercent == 20)

            let recreated = AppSettings(store: store)
            #expect(recreated.editorLineHeightMultiple == 2.0)
            #expect(recreated.editorParagraphSpacingLines == 0.25)
            #expect(recreated.editorLetterSpacingPercent == 20)
        }
    }

    @Test("AC-3: 行間は範囲の端か刻みに丸め、読めない値は初期値になる")
    func storedLineHeightMultiple() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Double)] = [
                (true, 1.0), ("1.5", 1.0), (Double.nan, 1.0), (Double.infinity, 1.0),
                (0.5, 1.0), (3.0, 2.0), (1.23, 1.2),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorLineHeightMultiple")
                #expect(store.value(SettingDefinitions.editorLineHeightMultiple) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorLineHeightMultiple == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: 段落の間隔は範囲の端か刻みに丸め、読めない値は初期値 0.25 になる")
    func storedParagraphSpacingLines() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Double)] = [
                (true, 0.25), ("1", 0.25), (Double.nan, 0.25),
                (-1, 0), (5, 2.0), (0.3, 0.25), (0, 0),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorParagraphSpacingLines")
                #expect(store.value(SettingDefinitions.editorParagraphSpacingLines) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorParagraphSpacingLines == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: 字間は範囲の端に丸め、読めない値は初期値 7 になる")
    func storedLetterSpacingPercent() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Int)] = [
                (-3, 0), (99, 20), (5, 5), (0, 0), ("5", 7), (true, 7), (Double.nan, 7), (Double.infinity, 7),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorLetterSpacingPercent")
                #expect(store.value(SettingDefinitions.editorLetterSpacingPercent) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorLetterSpacingPercent == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: カーソルの形は知っている名前だけを読み、知らない名前・文字列でない値は縦線になる")
    func storedCaretShape() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: EditorCaretShape)] = [
                ("block", .block), ("underline", .underline), ("bar", .bar),
                ("Block", .bar), ("", .bar), (1, .bar), (true, .bar),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorCaretShape")
                #expect(store.value(SettingDefinitions.editorCaretShape) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorCaretShape == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: 字下げと今いる行のハイライトは真偽値だけを読み、それ以外は初期値になる")
    func storedBooleans() throws {
        try withDefaults { store, defaults in
            for unreadable: Any in [1, 0, "YES", "false"] {
                defaults.set(unreadable, forKey: "editorIndentsWrappedLines")
                defaults.set(unreadable, forKey: "editorHighlightsCurrentLine")
                let settings = AppSettings(store: store)
                #expect(settings.editorIndentsWrappedLines == true, "\(unreadable)")
                #expect(settings.editorHighlightsCurrentLine == false, "\(unreadable)")
            }
        }
    }
}
