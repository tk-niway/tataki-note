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

    @Test("AC-22: 行間・段落の間隔・字間の値の表示が決めた形になる")
    func valueTextsHaveExpectedForm() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let settings = try makeSettings(suite: suite)
        let model = EditorSettingsModel(settings: settings)

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
    }

    @Test("AC-22: 初期値の表示は、行間 1.0 倍・段落の間隔 0.25 行・字間 7%")
    func initialValueTexts() throws {
        let suite = UUID().uuidString
        defer { removeSuite(suite) }
        let model = EditorSettingsModel(settings: try makeSettings(suite: suite))

        #expect(model.lineHeightText == "1.0 倍")
        #expect(model.paragraphSpacingText == "0.25 行")
        #expect(model.letterSpacingText == "7%")
    }

    @Test("AC-22: カーソルの形の表示名は「縦線」「ブロック」「下線」")
    func caretShapeDisplayNames() {
        #expect(EditorCaretShape.bar.displayName == "縦線")
        #expect(EditorCaretShape.block.displayName == "ブロック")
        #expect(EditorCaretShape.underline.displayName == "下線")
    }

    @Test("AC-25: 段落の間隔・字間・折り返した行の字下げの説明文は、20 文字以下で改行を含まず、数字と % を含まない")
    func descriptionsAreShort() {
        let descriptions = [
            EditorSettingsModel.paragraphSpacingDescription,
            EditorSettingsModel.letterSpacingDescription,
            EditorSettingsModel.wrapIndentDescription,
        ]
        for text in descriptions {
            #expect(!text.isEmpty, "\(text)")
            #expect(text.count <= 20, "\(text)")
            #expect(text.rangeOfCharacter(from: .newlines) == nil, "\(text)")
            #expect(!text.contains { $0.isNumber }, "\(text)")
            #expect(!text.contains("%") && !text.contains("％"), "\(text)")
        }
    }
}
