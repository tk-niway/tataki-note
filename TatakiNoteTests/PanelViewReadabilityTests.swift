import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct PanelViewReadabilityTests {
    private let sampleText = "- 長い箇条書きの項目\nふつうの段落"

    private func layout(of harness: PanelViewHarness) -> EditorTextLayout {
        EditorTextLayout(font: harness.settings.panelFont, readability: harness.settings.editorReadability)
    }

    private func loadedTextView(_ harness: PanelViewHarness) throws -> PromptTextView {
        let textView = try #require(harness.textView)
        harness.model.text = sampleText
        #expect(harness.settle { textView.string == sampleText })
        return textView
    }

    private func paragraphStyle(_ textView: PromptTextView, at location: Int) -> NSParagraphStyle? {
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private var secondParagraphStart: Int {
        ("- 長い箇条書きの項目\n" as NSString).length
    }

    // MARK: - AC-13

    @Test("AC-13: 開いたまま行間・段落の間隔・字間を変えると、入力欄の文章の属性がすぐにその値になる")
    func spacingSettingsReachOpenEditor() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        #expect(paragraphStyle(textView, at: 0)?.lineSpacing == 0)
        #expect(textView.textStorage?.attribute(.kern, at: 0, effectiveRange: nil) == nil)

        harness.settings.editorLineHeightMultiple = 1.5
        harness.settings.editorParagraphSpacingLines = 1
        harness.settings.editorLetterSpacingPercent = 10
        let expected = layout(of: harness)
        #expect(expected.lineSpacing > 0)
        #expect(expected.kern > 0)
        #expect(harness.settle { paragraphStyle(textView, at: 0)?.lineSpacing == expected.lineSpacing })

        for location in [0, secondParagraphStart] {
            let style = paragraphStyle(textView, at: location)
            #expect(style?.lineSpacing == expected.lineSpacing)
            #expect(style?.paragraphSpacing == expected.paragraphSpacing)
            #expect((textView.textStorage?.attribute(.kern, at: location, effectiveRange: nil) as? CGFloat) == expected.kern)
        }

        harness.settings.editorLineHeightMultiple = 1.0
        harness.settings.editorParagraphSpacingLines = 0
        harness.settings.editorLetterSpacingPercent = 0
        #expect(harness.settle { paragraphStyle(textView, at: 0)?.lineSpacing == 0 })
        #expect(paragraphStyle(textView, at: secondParagraphStart)?.paragraphSpacing == 0)
        #expect(textView.textStorage?.attribute(.kern, at: 0, effectiveRange: nil) == nil)
    }

    @Test("AC-13: 開いたまま字下げを切り替えると、箇条書きの段落の字下げがすぐに付き・外れる")
    func indentSettingReachesOpenEditor() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        #expect(harness.settle { (paragraphStyle(textView, at: 0)?.headIndent ?? 0) > 0 })
        #expect(paragraphStyle(textView, at: secondParagraphStart)?.headIndent == 0)

        harness.settings.editorIndentsWrappedLines = false
        #expect(harness.settle { paragraphStyle(textView, at: 0)?.headIndent == 0 })

        harness.settings.editorIndentsWrappedLines = true
        #expect(harness.settle { (paragraphStyle(textView, at: 0)?.headIndent ?? 0) > 0 })
    }

    @Test("AC-13: 開いたまま1行の長さの上限を変えると、入力欄の左右の余白がすぐに変わり、上限なしで元に戻る")
    func lineLengthSettingReachesOpenEditorInsets() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        let base = PanelMetrics.textContainerInset.width
        #expect(textView.textContainerInset.width == base)

        harness.settings.editorMaxLineLength = 20
        let maxWidth = try #require(layout(of: harness).maxContainerWidth)
        let expected = ((textView.bounds.width - maxWidth) / 2).rounded(.down)
        #expect(expected > base)
        #expect(harness.settle { textView.textContainerInset.width == expected })
        #expect(textView.textContainerOrigin.x == expected)

        harness.settings.editorMaxLineLength = nil
        #expect(harness.settle { textView.textContainerInset.width == base })
    }

    // MARK: - AC-12

    @Test("AC-12: 8つの設定を変えても、パネルの文章(モデルの text)と入力欄の文字は変わらない")
    func settingsKeepModelTextAndEditorText() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)

        harness.settings.editorLineHeightMultiple = 1.8
        harness.settings.editorParagraphSpacingLines = 0.75
        harness.settings.editorLetterSpacingPercent = 15
        harness.settings.editorMaxLineLength = 25
        harness.settings.editorIndentsWrappedLines = false
        harness.settings.editorCaretShape = .block
        harness.settings.editorCaretWidth = 4
        harness.settings.editorHighlightsCurrentLine = true
        let expected = layout(of: harness)
        #expect(harness.settle { paragraphStyle(textView, at: 0)?.lineSpacing == expected.lineSpacing })

        #expect(harness.model.text == sampleText)
        #expect(textView.string == sampleText)
        #expect(textView.textStorage?.string == sampleText)
    }

    // MARK: - AC-14

    @Test("AC-14: 最終行の下の余白は、行間を広げた1行の高さ × 余白の行数。行間 1.0 倍では基本の高さ × 行数")
    func bottomPaddingFollowsLineHeightMultiple() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        let base = EditorBottomPadding.lineHeight(for: harness.settings.panelFont)
        #expect(harness.settle { textView.bottomPadding == 3 * base })

        harness.settings.editorLineHeightMultiple = 1.5
        let widened = layout(of: harness).lineHeight
        #expect(abs(widened - 1.5 * base) < 0.0001)
        #expect(harness.settle { textView.bottomPadding == 3 * widened })
        #expect(textView.bottomPadding > 3 * base)

        harness.settings.editorBottomPaddingLines = 5
        #expect(harness.settle { textView.bottomPadding == 5 * widened })

        harness.settings.editorLineHeightMultiple = 1.0
        #expect(harness.settle { textView.bottomPadding == 5 * base })
    }

    // MARK: - AC-15

    @Test("AC-15: 1行の長さの上限で中央に寄せているとき、プレースホルダーの左端は入力欄の文章の始まりの位置にある")
    func placeholderLeadingMatchesCenteredTextStart() throws {
        let harness = try PanelViewHarness { $0.editorMaxLineLength = 20 }
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let base = PanelMetrics.textContainerInset.width
        #expect(harness.settle { textView.textContainerOrigin.x > base })
        let padding = try #require(textView.textContainer?.lineFragmentPadding)

        let leading = harness.hostingView.rootView.placeholderLeading(editorWidth: textView.bounds.width)

        #expect(leading == textView.textContainerOrigin.x + padding)
        #expect(leading > base + padding)
    }

    @Test("AC-15: 「上限なし」のプレースホルダーの左端は、今と同じ位置(基本の余白 + 行の余白)")
    func placeholderLeadingWithoutLimitIsUnchanged() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let padding = try #require(textView.textContainer?.lineFragmentPadding)

        let leading = harness.hostingView.rootView.placeholderLeading(editorWidth: textView.bounds.width)

        #expect(leading == PanelMetrics.textContainerInset.width + NSTextContainer().lineFragmentPadding)
        #expect(leading == textView.textContainerOrigin.x + padding)
    }

    @Test("AC-15: 開いたまま上限を変えると、プレースホルダーの左端も入力欄の文章の始まりについていく")
    func placeholderLeadingFollowsLimitChanges() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let padding = try #require(textView.textContainer?.lineFragmentPadding)

        harness.settings.editorMaxLineLength = 20
        #expect(harness.settle {
            harness.hostingView.rootView.placeholderLeading(editorWidth: textView.bounds.width)
                == textView.textContainerOrigin.x + padding
                && textView.textContainerOrigin.x > PanelMetrics.textContainerInset.width
        })

        harness.settings.editorMaxLineLength = nil
        #expect(harness.settle {
            harness.hostingView.rootView.placeholderLeading(editorWidth: textView.bounds.width)
                == PanelMetrics.textContainerInset.width + padding
        })
    }
}
