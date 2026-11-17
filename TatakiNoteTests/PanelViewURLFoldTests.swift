import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct PanelViewURLFoldTests {
    private let url = "https://example.com/docs/2026/11/some-page"
    private var sampleText: String { "前置き\n\(url)\n後書き" }

    private func hiddenCount(_ textView: PromptTextView, in range: NSRange) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        return (range.location..<NSMaxRange(range)).filter {
            storage.attribute(.editorURLHidden, at: $0, effectiveRange: nil) != nil
        }.count
    }

    private func loadedTextView(_ harness: PanelViewHarness) throws -> PromptTextView {
        let textView = try #require(harness.textView)
        harness.model.text = sampleText
        #expect(harness.settle { textView.string == sampleText })
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return textView
    }

    // MARK: - AC-12

    @Test("AC-12: URL を畳んで表示していても、パネルの文章は URL の全文のまま")
    func panelTextKeepsFullURL() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        let range = (sampleText as NSString).range(of: url)
        #expect(harness.settle { hiddenCount(textView, in: range) > 0 })

        #expect(harness.model.text == sampleText)
        #expect(harness.model.text.contains(url))
        #expect(textView.string == sampleText)
        #expect(textView.textStorage?.string == sampleText)
    }

    // MARK: - AC-13

    @Test("AC-13: 開いたまま「URL を畳む」を切り替えると、入力欄の見え方がすぐに変わる")
    func foldSettingReachesOpenEditor() throws {
        let harness = try PanelViewHarness()
        defer { harness.removeDefaults() }
        let textView = try loadedTextView(harness)
        let range = (sampleText as NSString).range(of: url)
        #expect(harness.settings.editorFoldsURLs)
        #expect(harness.settle { hiddenCount(textView, in: range) > 0 })
        #expect(!textView.urlPresentations.isEmpty)

        harness.settings.editorFoldsURLs = false
        #expect(harness.settle { hiddenCount(textView, in: range) == 0 })
        #expect(textView.urlPresentations.allSatisfy { $0.fold == nil })
        #expect(textView.appliedHiddenKerns.isEmpty)
        #expect(textView.string == sampleText)
        #expect(harness.model.text == sampleText)

        harness.settings.editorFoldsURLs = true
        #expect(harness.settle { hiddenCount(textView, in: range) > 0 })
        #expect(textView.urlPresentations.contains { $0.fold != nil })
        #expect(harness.model.text == sampleText)
    }
}
