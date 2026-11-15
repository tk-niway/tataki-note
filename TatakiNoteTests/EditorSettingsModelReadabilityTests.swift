import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct EditorSettingsModelReadabilityTests {
    private func makeSettings(suite name: String) throws -> AppSettings {
        try TemporaryDefaults(name: name).makeSettings()
    }

    private func removeSuite(_ name: String) {
        TemporaryDefaults.remove(named: name)
    }

    @Test("AC-22: 行間・段落の間隔・字間・カーソルの太さの値の表示が決めた形になる")
    func valueTextsHaveExpectedForm() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(model.caretWidthText == "2 pt")
        #expect(model.lineHeightText == "1.0 倍")
        settings.editorLineHeightMultiple = 1.5
        #expect(model.lineHeightText == "1.5 倍")
        settings.editorLineHeightMultiple = 2.0
        #expect(model.lineHeightText == "2.0 倍")

        let paragraphCases: [(Double, String)] = [
            (0, "0 行"), (0.25, "0.25 行"), (0.5, "0.5 行"), (1, "1 行"), (1.75, "1.75 行"), (2, "2 行"),
        ]
        for (value, expected) in paragraphCases {
            settings.editorParagraphSpacingLines = value
            #expect(model.paragraphSpacingText == expected)
        }

        settings.editorLetterSpacingPercent = 0
        #expect(model.letterSpacingText == "0%")
        settings.editorLetterSpacingPercent = 5
        #expect(model.letterSpacingText == "5%")
        settings.editorLetterSpacingPercent = 20
        #expect(model.letterSpacingText == "20%")

        settings.editorCaretWidth = 1
        #expect(model.caretWidthText == "1 pt")
        settings.editorCaretWidth = 4
        #expect(model.caretWidthText == "4 pt")
    }

    @Test("AC-22: 1行の長さの上限の表示は「上限なし」か「N 文字」になる")
    func maxLineLengthText() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(model.maxLineLengthText == "上限なし")
        settings.editorMaxLineLength = 40
        #expect(model.maxLineLengthText == "40 文字")
        settings.editorMaxLineLength = 20
        #expect(model.maxLineLengthText == "20 文字")
        settings.editorMaxLineLength = 80
        #expect(model.maxLineLengthText == "80 文字")
    }

    @Test("AC-22: 1行の長さの上限のステッパーは …75・80・上限なし の順に進み、端で止まる")
    func maxLineLengthStepperWalksAndStops() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        settings.editorMaxLineLength = 70
        model.incrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 75)
        model.incrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 80)
        model.incrementMaxLineLength()
        #expect(settings.editorMaxLineLength == nil)
        #expect(model.maxLineLengthText == "上限なし")
        model.incrementMaxLineLength()
        #expect(settings.editorMaxLineLength == nil)

        model.decrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 80)
        model.decrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 75)

        settings.editorMaxLineLength = 25
        model.decrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 20)
        model.decrementMaxLineLength()
        #expect(settings.editorMaxLineLength == 20)
    }

    @Test("AC-22: カーソルの形が「ブロック」「下線」の間は太さを変えられず、「縦線」に戻すと変えられる")
    func caretWidthIsEnabledOnlyForBar() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

        #expect(settings.editorCaretShape == .bar)
        #expect(model.isCaretWidthEnabled)
        settings.editorCaretShape = .block
        #expect(!model.isCaretWidthEnabled)
        settings.editorCaretShape = .underline
        #expect(!model.isCaretWidthEnabled)
        settings.editorCaretShape = .bar
        #expect(model.isCaretWidthEnabled)
    }

    @Test("AC-22: カーソルの形の表示名は「縦線」「ブロック」「下線」")
    func caretShapeDisplayNames() {
        #expect(EditorCaretShape.bar.displayName == "縦線")
        #expect(EditorCaretShape.block.displayName == "ブロック")
        #expect(EditorCaretShape.underline.displayName == "下線")
    }
}
