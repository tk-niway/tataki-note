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
        "editorMaxLineLength",
        "editorIndentsWrappedLines",
        "editorCaretShape",
        "editorCaretWidth",
        "editorHighlightsCurrentLine",
    ]

    @Test("AC-1: 8つのキーが無い前の版の利用者は、初期値になる")
    func missingKeysAreDefaults() throws {
        try withDefaults { store, defaults in
            for key in Self.keys {
                #expect(defaults.object(forKey: key) == nil, "\(key)")
            }
            let settings = AppSettings(store: store)
            #expect(settings.editorLineHeightMultiple == 1.0)
            #expect(settings.editorParagraphSpacingLines == 0)
            #expect(settings.editorLetterSpacingPercent == 0)
            #expect(settings.editorMaxLineLength == nil)
            #expect(settings.editorIndentsWrappedLines == true)
            #expect(settings.editorCaretShape == .bar)
            #expect(settings.editorCaretWidth == 2)
            #expect(settings.editorHighlightsCurrentLine == false)
            #expect(settings.editorReadability == EditorReadability.standard)
        }
    }

    @Test("AC-2: 変えた8つの項目は、その場で保存され、設定を作り直しても残る")
    func changedValuesAreSavedAndSurviveRecreation() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)

            settings.editorLineHeightMultiple = 1.5
            settings.editorParagraphSpacingLines = 0.5
            settings.editorLetterSpacingPercent = 8
            settings.editorMaxLineLength = 40
            settings.editorIndentsWrappedLines = false
            settings.editorCaretShape = .block
            settings.editorCaretWidth = 3
            settings.editorHighlightsCurrentLine = true

            #expect(defaults.object(forKey: "editorLineHeightMultiple") as? Double == 1.5)
            #expect(defaults.object(forKey: "editorParagraphSpacingLines") as? Double == 0.5)
            #expect(defaults.object(forKey: "editorLetterSpacingPercent") as? Int == 8)
            #expect(defaults.object(forKey: "editorMaxLineLength") as? Int == 40)
            #expect(defaults.object(forKey: "editorIndentsWrappedLines") as? Bool == false)
            #expect(defaults.object(forKey: "editorCaretShape") as? String == "block")
            #expect(defaults.object(forKey: "editorCaretWidth") as? Int == 3)
            #expect(defaults.object(forKey: "editorHighlightsCurrentLine") as? Bool == true)

            let recreated = AppSettings(store: store)
            #expect(recreated.editorReadability == EditorReadability(
                lineHeightMultiple: 1.5,
                paragraphSpacingLines: 0.5,
                letterSpacingPercent: 8,
                maxLineLength: 40,
                indentsWrappedLines: false,
                caretShape: .block,
                caretWidth: 3,
                highlightsCurrentLine: true
            ))
            #expect(settings.editorReadability == recreated.editorReadability)
        }
    }

    @Test("AC-2: 1行の長さの上限を「上限なし」に戻すとキーが消える")
    func clearingMaxLineLengthRemovesKey() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)
            settings.editorMaxLineLength = 60
            #expect(defaults.object(forKey: "editorMaxLineLength") as? Int == 60)

            settings.editorMaxLineLength = nil
            #expect(defaults.object(forKey: "editorMaxLineLength") == nil)
            #expect(AppSettings(store: store).editorMaxLineLength == nil)
        }
    }

    @Test("AC-2: 範囲の外や刻みに乗らない値を入れても、丸めて保存する")
    func assignedValuesAreNormalizedBeforeSaving() throws {
        try withDefaults { store, defaults in
            let settings = AppSettings(store: store)

            settings.editorLineHeightMultiple = 5
            #expect(settings.editorLineHeightMultiple == 2.0)
            settings.editorParagraphSpacingLines = 0.3
            #expect(settings.editorParagraphSpacingLines == 0.25)
            settings.editorLetterSpacingPercent = 99
            #expect(settings.editorLetterSpacingPercent == 20)
            settings.editorMaxLineLength = 23
            #expect(settings.editorMaxLineLength == 25)
            settings.editorCaretWidth = 0
            #expect(settings.editorCaretWidth == 1)

            let recreated = AppSettings(store: store)
            #expect(recreated.editorLineHeightMultiple == 2.0)
            #expect(recreated.editorParagraphSpacingLines == 0.25)
            #expect(recreated.editorLetterSpacingPercent == 20)
            #expect(recreated.editorMaxLineLength == 25)
            #expect(recreated.editorCaretWidth == 1)
            #expect(defaults.object(forKey: "editorMaxLineLength") as? Int == 25)
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

    @Test("AC-3: 段落の間隔は範囲の端か刻みに丸め、読めない値は初期値になる")
    func storedParagraphSpacingLines() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Double)] = [
                (true, 0), ("1", 0), (Double.nan, 0),
                (-1, 0), (5, 2.0), (0.3, 0.25),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorParagraphSpacingLines")
                #expect(store.value(SettingDefinitions.editorParagraphSpacingLines) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorParagraphSpacingLines == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: 字間は範囲の端に丸め、読めない値は初期値になる")
    func storedLetterSpacingPercent() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Int)] = [
                (-3, 0), (99, 20), (7, 7), ("5", 0), (true, 0), (Double.nan, 0), (Double.infinity, 0),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorLetterSpacingPercent")
                #expect(store.value(SettingDefinitions.editorLetterSpacingPercent) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorLetterSpacingPercent == expected, "\(stored)")
            }
        }
    }

    @Test("AC-3: 1行の長さの上限は範囲の端か 5 の倍数に丸め、読めない値は上限なしになる")
    func storedMaxLineLength() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Int?)] = [
                (true, nil), ("40", nil), (Double.nan, nil), (Double.infinity, nil),
                (10, 20), (99, 80), (22, 20), (23, 25), (40, 40),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorMaxLineLength")
                #expect(store.value(SettingDefinitions.editorMaxLineLength) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorMaxLineLength == expected, "\(stored)")
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

    @Test("AC-3: カーソルの太さは範囲の端に丸め、読めない値は初期値になる")
    func storedCaretWidth() throws {
        try withDefaults { store, defaults in
            let cases: [(stored: Any, expected: Int)] = [
                (0, 1), (9, 4), (3, 3), (true, 2), ("3", 2), (Double.nan, 2),
            ]
            for (stored, expected) in cases {
                defaults.set(stored, forKey: "editorCaretWidth")
                #expect(store.value(SettingDefinitions.editorCaretWidth) == expected, "\(stored)")
                #expect(AppSettings(store: store).editorCaretWidth == expected, "\(stored)")
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
