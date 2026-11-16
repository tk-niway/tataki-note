import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class FoldFindFixture {
    static let font = NSFont.systemFont(ofSize: 14)
    static let longURL = "https://example.com/docs/2026/11/some-page"
    static let wrappingURL = "https://example.com/"
        + (1...12).map { "segment\($0)-with-some-words" }.joined(separator: "/")

    static let readability = EditorReadability(
        lineHeightMultiple: 1.5,
        paragraphSpacingLines: 1,
        letterSpacingPercent: 10,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: true
    )

    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let pasteboard = PasteboardFixture.makePasteboard()

    init(
        _ text: String,
        foldsURLs: Bool = true,
        selection: NSRange = NSRange(location: 0, length: 0)
    ) {
        textView.isRichText = false
        textView.pasteboard = pasteboard
        textView.applyFont(Self.font)
        textView.applyReadability(Self.readability)
        textView.foldsURLs = foldsURLs
        textView.string = text
        textView.setSelectedRange(selection)
        layOutAll()
        textView.refreshCaret()
    }

    func layOutAll() {
        guard let layoutManager = textView.textLayoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
    }

    isolated deinit {
        pasteboard.releaseGlobally()
    }

    func range(of target: String) -> NSRange {
        (textView.string as NSString).range(of: target)
    }

    func hiddenCount(in range: NSRange) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        return (range.location..<NSMaxRange(range)).filter {
            storage.attribute(.editorURLHidden, at: $0, effectiveRange: nil) != nil
        }.count
    }

    func renderedColor(_ key: NSAttributedString.Key, at location: Int) -> NSColor? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: location)
        else { return nil }
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) {
                color = attributes[key] as? NSColor
            }
            return false
        }
        return color
    }
}

@MainActor
struct PromptTextViewURLFoldFindTests {
    private static let long = FoldFindFixture.longURL
    private static let wrapping = FoldFindFixture.wrappingURL
    private static let wrappingText = "先頭\n\(wrapping) 後書き\n最後の行です"

    private func lastLineSelection(of text: String) -> NSRange {
        NSRange(location: (text as NSString).range(of: "最後の行です").location, length: 0)
    }

    // MARK: - AC-11

    @Test("AC-11: 検索の一致が畳んだ URL の中にあると開き、検索を閉じて一致が消えると畳む。ハイライトは残る")
    func matchInsideURLOpensAndClosingFolds() throws {
        let text = Self.wrappingText
        let atLast = lastLineSelection(of: text)
        let fixture = FoldFindFixture(text, selection: atLast)
        let url = fixture.range(of: Self.wrapping)
        let match = NSRange(location: url.location + 100, length: 6)
        #expect(fixture.hiddenCount(in: url) > 0)

        fixture.textView.showFindHighlights([match], current: match)
        #expect(fixture.hiddenCount(in: url) == 0)
        #expect(fixture.textView.findHighlights.map(\.range) == [match])
        #expect(fixture.renderedColor(.backgroundColor, at: match.location) == FindHighlighter.currentColor)
        #expect(fixture.renderedColor(.foregroundColor, at: url.location) == EditorURLFoldStyler.urlColor)

        fixture.textView.showFindHighlights([], current: nil)
        #expect(fixture.hiddenCount(in: url) > 0)
        #expect(fixture.renderedColor(.backgroundColor, at: match.location) == nil)
        #expect(fixture.textView.string == text)
    }

    @Test("AC-11: 一致が URL の外なら畳んだまま。ほかの一致のハイライトも付く")
    func matchOutsideURLKeepsFold() {
        let text = Self.wrappingText
        let fixture = FoldFindFixture(text, selection: lastLineSelection(of: text))
        let url = fixture.range(of: Self.wrapping)
        let outside = fixture.range(of: "後書き")
        let before = fixture.hiddenCount(in: url)
        #expect(before > 0)

        fixture.textView.showFindHighlights([outside], current: outside)
        #expect(fixture.hiddenCount(in: url) == before)
        #expect(fixture.renderedColor(.backgroundColor, at: outside.location) == FindHighlighter.currentColor)
    }

    @Test("AC-11: 一致を付けたまま URL から離れた所でカーソルを動かしても、検索のハイライトと URL の色が残る")
    func movingCaretAwayFromURLKeepsFindHighlights() {
        let text = Self.wrappingText
        let atLast = lastLineSelection(of: text)
        let fixture = FoldFindFixture(text, selection: atLast)
        let url = fixture.range(of: Self.wrapping)
        let outside = fixture.range(of: "後書き")
        let hostStart = url.location + "https://".count
        fixture.textView.showFindHighlights([outside], current: outside)
        let hiddenBefore = fixture.hiddenCount(in: url)
        #expect(hiddenBefore > 0)

        fixture.textView.setSelectedRange(NSRange(location: atLast.location + 1, length: 0))
        fixture.textView.setSelectedRange(NSRange(location: atLast.location + 2, length: 0))

        #expect(fixture.renderedColor(.backgroundColor, at: outside.location) == FindHighlighter.currentColor)
        #expect(fixture.renderedColor(.foregroundColor, at: hostStart) == EditorURLFoldStyler.urlColor)
        #expect(fixture.renderedColor(.foregroundColor, at: url.location)?.alphaComponent == 0)
        #expect(fixture.hiddenCount(in: url) == hiddenBefore)
    }

    @Test("AC-11: 一致で開いた後のカーソルは、開いた配置での位置で、refreshCaret を呼んでも変わらない")
    func caretFollowsFindOpening() throws {
        let text = Self.wrappingText
        let atLast = lastLineSelection(of: text)
        let fixture = FoldFindFixture(text, selection: atLast)
        let opened = FoldFindFixture(text, foldsURLs: false, selection: atLast)
        let url = fixture.range(of: Self.wrapping)
        let match = NSRange(location: url.location + 100, length: 6)
        let foldedCaret = try #require(fixture.textView.caretView?.caretRect)

        fixture.textView.showFindHighlights([match], current: match)
        #expect(fixture.hiddenCount(in: url) == 0)
        let openCaret = try #require(fixture.textView.caretView?.caretRect)
        #expect(openCaret == opened.textView.caretView?.caretRect)
        #expect(openCaret != foldedCaret)
        fixture.textView.refreshCaret()
        #expect(fixture.textView.caretView?.caretRect == openCaret)
    }

    @Test("AC-11: 一致で開いた後の今いる行のハイライトは、開いた配置での位置で、refreshCaret を呼んでも変わらない")
    func lineHighlightFollowsFindOpening() throws {
        let text = Self.wrappingText
        let atLast = lastLineSelection(of: text)
        let fixture = FoldFindFixture(text, selection: atLast)
        let opened = FoldFindFixture(text, foldsURLs: false, selection: atLast)
        let url = fixture.range(of: Self.wrapping)
        let match = NSRange(location: url.location + 100, length: 6)
        #expect(FindHighlighter.rects(for: url, in: opened.textView).count >= 2)
        let foldedHighlight = try #require(fixture.textView.currentLineHighlightRect)

        fixture.textView.showFindHighlights([match], current: match)
        let openHighlight = try #require(fixture.textView.currentLineHighlightRect)
        #expect(openHighlight != foldedHighlight)
        #expect(openHighlight == opened.textView.currentLineHighlightRect)
        fixture.textView.refreshCaret()
        #expect(fixture.textView.currentLineHighlightRect == openHighlight)
    }

    @Test("AC-11: 検索を閉じて畳んだ後のカーソルと今いる行のハイライトは、畳んだ配置での位置で、refreshCaret を呼んでも変わらない")
    func caretAndLineHighlightFollowFindClosing() throws {
        let text = Self.wrappingText
        let atLast = lastLineSelection(of: text)
        let fixture = FoldFindFixture(text, selection: atLast)
        let settled = FoldFindFixture(text, selection: atLast)
        let url = fixture.range(of: Self.wrapping)
        let match = NSRange(location: url.location + 100, length: 6)

        fixture.textView.showFindHighlights([match], current: match)
        fixture.textView.showFindHighlights([], current: nil)
        #expect(fixture.hiddenCount(in: url) > 0)
        let foldedCaret = try #require(fixture.textView.caretView?.caretRect)
        let foldedHighlight = try #require(fixture.textView.currentLineHighlightRect)
        #expect(foldedCaret == settled.textView.caretView?.caretRect)
        #expect(foldedHighlight == settled.textView.currentLineHighlightRect)
        fixture.textView.refreshCaret()
        #expect(fixture.textView.caretView?.caretRect == foldedCaret)
        #expect(fixture.textView.currentLineHighlightRect == foldedHighlight)
    }

    @Test("AC-11: revealFindMatch で一致の URL に選択が移ると開き、外の一致に移ると畳む")
    func revealFindMatchTogglesFold() {
        let text = Self.wrappingText
        let fixture = FoldFindFixture(text, selection: lastLineSelection(of: text))
        let url = fixture.range(of: Self.wrapping)
        let inside = NSRange(location: url.location + 100, length: 6)
        let outside = fixture.range(of: "後書き")

        fixture.textView.revealFindMatch(inside)
        #expect(fixture.hiddenCount(in: url) == 0)
        #expect(fixture.textView.selectedRange() == inside)

        fixture.textView.revealFindMatch(outside)
        #expect(fixture.hiddenCount(in: url) > 0)
        #expect(fixture.textView.selectedRange() == outside)
    }

    // MARK: - AC-12

    private static let copyText = "前置き\n\(long) 後書き\n最後の行です"

    private func caretAfterURL(_ fixture: FoldFindFixture) -> NSRange {
        let tail = fixture.range(of: "後書き")
        return NSRange(location: NSMaxRange(tail), length: 0)
    }

    @Test("AC-12: 畳んだ URL を含む選択のコピーは URL の全文を含む")
    func selectionCopyContainsFullURL() {
        let fixture = FoldFindFixture(Self.copyText)
        let selection = NSRange(location: 0, length: NSMaxRange(fixture.range(of: "後書き")))
        fixture.textView.setSelectedRange(selection)
        let url = fixture.range(of: Self.long)
        #expect(fixture.hiddenCount(in: url) > 0)

        fixture.textView.writeSelection(to: fixture.pasteboard, types: fixture.textView.writablePasteboardTypes)

        let copied = fixture.pasteboard.string(forType: .string)
        #expect(copied == "前置き\n\(Self.long) 後書き")
        #expect(copied?.contains(Self.long) == true)
    }

    @Test("AC-12: 畳んだ URL を含む選択の切り取りは、URL の全文を書き出して選択を消す")
    func selectionCutContainsFullURLAndRemovesIt() {
        let fixture = FoldFindFixture(Self.copyText)
        let selection = NSRange(location: 0, length: NSMaxRange(fixture.range(of: "後書き")))
        fixture.textView.setSelectedRange(selection)
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) > 0)

        fixture.textView.writeSelection(to: fixture.pasteboard, types: fixture.textView.writablePasteboardTypes)
        fixture.textView.insertText("", replacementRange: fixture.textView.selectedRange())

        #expect(fixture.pasteboard.string(forType: .string) == "前置き\n\(Self.long) 後書き")
        #expect(fixture.textView.string == "\n最後の行です")
    }

    @Test("AC-12: 畳んだ URL のある行の行ごとのコピーは URL の全文を含む")
    func lineCopyContainsFullURL() {
        let fixture = FoldFindFixture(Self.copyText)
        fixture.textView.setSelectedRange(caretAfterURL(fixture))
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) > 0)

        fixture.textView.copyLineOrSelection()

        #expect(fixture.pasteboard.string(forType: .string) == "\(Self.long) 後書き\n")
        #expect(fixture.textView.string == Self.copyText)
    }

    @Test("AC-12: 畳んだ URL のある行の行ごとの切り取りは URL の全文を書き出して行を消す")
    func lineCutContainsFullURL() {
        let fixture = FoldFindFixture(Self.copyText)
        fixture.textView.setSelectedRange(caretAfterURL(fixture))
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) > 0)

        fixture.textView.cutLineOrSelection()

        #expect(fixture.pasteboard.string(forType: .string) == "\(Self.long) 後書き\n")
        #expect(fixture.textView.string == "前置き\n最後の行です")
    }

    // MARK: - AC-13

    @Test("AC-13: 文章とカーソルを変えずにオフからオンに戻すと、隠す文字に負の字間と色が付き直す")
    func switchingOffThenOnReappliesKernAndColor() throws {
        let text = "前置き\n\(Self.long)\n後書き"
        let fixture = FoldFindFixture(text)
        let url = fixture.range(of: Self.long)
        let storage = try #require(fixture.textView.textStorage)
        let layout = EditorTextLayout(font: FoldFindFixture.font, readability: FoldFindFixture.readability)

        let schemeRange = NSRange(location: url.location, length: "https://".count)

        func schemeKerns() -> [CGFloat] {
            (schemeRange.location..<NSMaxRange(schemeRange)).compactMap { location in
                guard storage.attribute(.editorURLHidden, at: location, effectiveRange: nil) != nil else { return nil }
                return (storage.attribute(.kern, at: location, effectiveRange: nil) as? NSNumber).map { CGFloat($0.doubleValue) }
            }
        }

        #expect(schemeKerns().count == schemeRange.length)
        #expect(schemeKerns().allSatisfy { $0 < 0 })

        fixture.textView.foldsURLs = false
        #expect(fixture.hiddenCount(in: url) == 0)
        #expect(fixture.renderedColor(.foregroundColor, at: url.location) == nil)
        #expect(fixture.renderedColor(.foregroundColor, at: NSMaxRange(url) - 1) == nil)
        for location in url.location..<NSMaxRange(url) {
            let kern = (storage.attribute(.kern, at: location, effectiveRange: nil) as? NSNumber).map { CGFloat($0.doubleValue) }
            #expect(kern == layout.kern)
        }

        fixture.textView.foldsURLs = true
        #expect(schemeKerns().count == schemeRange.length)
        #expect(schemeKerns().allSatisfy { $0 < 0 })
        #expect(fixture.hiddenCount(in: url) > schemeRange.length)
        #expect(fixture.renderedColor(.foregroundColor, at: url.location)?.alphaComponent == 0)
        #expect(fixture.renderedColor(.foregroundColor, at: NSMaxRange(url) - 1) == EditorURLFoldStyler.urlColor)
        #expect(fixture.textView.string == text)
    }
}
