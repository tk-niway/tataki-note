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
        let initial = layout(of: harness)
        #expect(paragraphStyle(textView, at: 0)?.lineSpacing == 0)
        #expect(paragraphStyle(textView, at: 0)?.paragraphSpacing == initial.paragraphSpacing)
        #expect(initial.paragraphSpacing > 0)
        #expect((textView.textStorage?.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat) == initial.kern)
        #expect(initial.kern > 0)

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

    // MARK: - AC-12

    @Test("AC-12: 6つの設定を変えても、パネルの文章(モデルの text)と入力欄の文字は変わらない")
    func settingsKeepModelTextAndEditorText() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)

        harness.settings.editorLineHeightMultiple = 1.8
        harness.settings.editorParagraphSpacingLines = 0.75
        harness.settings.editorLetterSpacingPercent = 15
        harness.settings.editorIndentsWrappedLines = false
        harness.settings.editorCaretShape = .block
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

    // MARK: - AC-26

    private func applyNonDefaultSettings(_ settings: AppSettings) {
        settings.editorLineHeightMultiple = 2.0
        settings.editorParagraphSpacingLines = 2
        settings.editorLetterSpacingPercent = 20
        settings.editorIndentsWrappedLines = false
        settings.editorCaretShape = .block
        settings.editorHighlightsCurrentLine = true
    }

    @Test("AC-26: 6つの設定をどれも初期値と違う値にしても、入力欄の左右の余白は今と同じで、パネルの幅を変えても変わらない")
    func horizontalInsetIsIndependentOfSettings() throws {
        let harness = try PanelViewHarness(configure: applyNonDefaultSettings)
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let expected = PanelMetrics.textContainerInset

        #expect(harness.settle { textView.textLayout?.readability == harness.settings.editorReadability })
        #expect(textView.textContainerInset.width == expected.width)
        #expect(textView.textContainerOrigin.x == expected.width)

        for width in [800, PanelMetrics.defaultSize.width - 100] {
            harness.panel.setContentSize(NSSize(width: width, height: PanelMetrics.defaultSize.height))
            #expect(harness.settle { textView.bounds.width > 0 })
            #expect(textView.textContainerInset.width == expected.width, "幅 \(width)")
            #expect(textView.textContainerOrigin.x == expected.width, "幅 \(width)")
        }
    }

    @Test("AC-26: 入力欄は、設定によらず幅いっぱい(左右の余白を除いた幅)で折り返す")
    func textContainerFillsEditorWidth() throws {
        let harness = try PanelViewHarness(configure: applyNonDefaultSettings)
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let container = try #require(textView.textContainer)

        for width in [PanelMetrics.defaultSize.width + 200, PanelMetrics.defaultSize.width] {
            harness.panel.setContentSize(NSSize(width: width, height: PanelMetrics.defaultSize.height))
            #expect(harness.settle {
                abs(container.size.width - (textView.bounds.width - 2 * PanelMetrics.textContainerInset.width)) < 1
            }, "幅 \(width)")
        }
    }

    @Test("AC-26: 空の入力欄のプレースホルダーの左上は、入力欄の文章の始まりの位置にあり、どの設定でも変わらない")
    func placeholderInsetMatchesTextStart() throws {
        let harness = try PanelViewHarness(configure: applyNonDefaultSettings)
        defer { harness.removeDefaults() }
        let textView = try #require(harness.textView)
        let padding = try #require(textView.textContainer?.lineFragmentPadding)

        #expect(PanelView.placeholderInset.width == textView.textContainerOrigin.x + padding)
        #expect(PanelView.placeholderInset.width == PanelMetrics.textContainerInset.width + NSTextContainer().lineFragmentPadding)
        #expect(PanelView.placeholderInset.height == textView.textContainerOrigin.y)
    }
}
