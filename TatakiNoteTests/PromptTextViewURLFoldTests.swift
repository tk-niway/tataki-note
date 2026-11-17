import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class FoldUndoDelegate: NSObject, NSTextViewDelegate {
    let textUndoManager = UndoManager()

    override init() {
        textUndoManager.groupsByEvent = false
        super.init()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textUndoManager
    }
}

@MainActor
private final class FoldFixture {
    static let font = NSFont.systemFont(ofSize: 14)
    static let shortURL = "https://example.com/short"
    static let longURL = "https://example.com/docs/2026/11/some-page"
    static let wrappingURL = "https://example.com/"
        + (1...12).map { "segment\($0)-with-some-words" }.joined(separator: "/")

    static let readability = EditorReadability(
        lineHeightMultiple: 1.5,
        paragraphSpacingLines: 1,
        letterSpacingPercent: 10,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let delegate = FoldUndoDelegate()
    let text: String

    init(
        _ text: String,
        readability: EditorReadability = FoldFixture.readability,
        foldsURLs: Bool = true,
        selection: NSRange = NSRange(location: 0, length: 0),
        undo: Bool = false
    ) {
        self.text = text
        textView.isRichText = false
        if undo {
            textView.allowsUndo = true
            textView.delegate = delegate
        }
        textView.applyFont(Self.font)
        textView.applyReadability(readability)
        textView.foldsURLs = foldsURLs
        textView.string = text
        textView.setSelectedRange(selection)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        textView.refreshCaret()
    }

    var undoManager: UndoManager {
        delegate.textUndoManager
    }

    func range(of target: String) -> NSRange {
        (textView.string as NSString).range(of: target)
    }

    var storage: NSTextStorage {
        textView.textStorage ?? NSTextStorage()
    }

    func kern(at location: Int) -> CGFloat? {
        (storage.attribute(.kern, at: location, effectiveRange: nil) as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    func isHidden(at location: Int) -> Bool {
        storage.attribute(.editorURLHidden, at: location, effectiveRange: nil) != nil
    }

    func hiddenCount(in range: NSRange) -> Int {
        (range.location..<NSMaxRange(range)).filter { isHidden(at: $0) }.count
    }

    func rect(of range: NSRange) -> CGRect {
        FindHighlighter.rects(for: range, in: textView).reduce(CGRect.null) { $0.union($1) }
    }

    func width(of range: NSRange) -> CGFloat {
        rect(of: range).width
    }

    func renderedColor(at location: Int) -> NSColor? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: location)
        else { return nil }
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) {
                color = attributes[.foregroundColor] as? NSColor
            }
            return false
        }
        return color
    }

    func type(_ string: String, at range: NSRange) {
        undoManager.beginUndoGrouping()
        if textView.shouldChangeText(in: range, replacementString: string) {
            textView.textStorage?.replaceCharacters(
                in: range,
                with: NSAttributedString(string: string, attributes: textView.typingAttributes)
            )
            textView.didChangeText()
        }
        undoManager.endUndoGrouping()
    }

    func insert(_ string: String) {
        textView.insertText(string, replacementRange: textView.selectedRange())
    }
}

@MainActor
struct PromptTextViewURLFoldTests {
    private static let long = FoldFixture.longURL
    private static let short = FoldFixture.shortURL
    private static let sample = "前置き\n\(short)\nと\n\(long)\n後書き"
    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    private var layout: EditorTextLayout {
        EditorTextLayout(font: FoldFixture.font, readability: FoldFixture.readability)
    }

    private func isUnfolded(_ fixture: FoldFixture, _ range: NSRange) -> Bool {
        fixture.hiddenCount(in: range) == 0
    }

    private func isSame(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 0.5 && abs(first.minY - second.minY) < 0.5
            && abs(first.width - second.width) < 0.5 && abs(first.height - second.height) < 0.5
    }

    // MARK: - AC-5

    @Test("AC-5: 30 文字を超える URL は幅が全文より狭くなり、「…」の位置が URL の矩形の中にある")
    func longURLIsNarrowerAndEllipsisIsInsideItsRect() throws {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.long)

        #expect(fixture.width(of: url) < plain.width(of: url) - 20)
        #expect(fixture.textView.urlPresentations.contains { $0.fold != nil })

        let ellipses = fixture.textView.urlEllipsisRects()
        #expect(ellipses.count == 1)
        let urlRect = fixture.rect(of: url)
        let ellipsis = try #require(ellipses.first)
        #expect(ellipsis.minX > urlRect.minX + 20)
        #expect(ellipsis.minX < urlRect.maxX)
        #expect(ellipsis.maxY > urlRect.minY)
        #expect(ellipsis.minY < urlRect.maxY)
        #expect(fixture.textView.string == Self.sample)
    }

    @Test("AC-5: 30 文字以下の URL は幅が変わらない")
    func shortURLKeepsItsWidth() {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.short)

        #expect(abs(fixture.width(of: url) - plain.width(of: url)) < 0.5)
        #expect(isUnfolded(fixture, url))
    }

    @Test("AC-5: どちらの URL も地の文と違う色で、隠す文字は透明、文章は変わらない")
    func urlsAreColoured() {
        let fixture = FoldFixture(Self.sample)
        let long = fixture.range(of: Self.long)
        let short = fixture.range(of: Self.short)

        #expect(fixture.renderedColor(at: short.location) == EditorURLFoldStyler.urlColor)
        #expect(fixture.renderedColor(at: NSMaxRange(long) - 1) == EditorURLFoldStyler.urlColor)
        #expect(fixture.renderedColor(at: long.location)?.alphaComponent == 0)
        #expect(fixture.renderedColor(at: 0) == nil)
        #expect(fixture.textView.string == Self.sample)
    }

    @Test("AC-5: 設定をオフにすると畳みも色も外れ、オンに戻すとまた畳まれる")
    func switchingOffRestoresAndSwitchingOnFoldsAgain() {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.long)
        let folded = fixture.width(of: url)

        fixture.textView.foldsURLs = false
        #expect(abs(fixture.width(of: url) - plain.width(of: url)) < 0.5)
        #expect(fixture.hiddenCount(in: url) == 0)
        #expect(fixture.renderedColor(at: url.location) == nil)
        #expect(!fixture.textView.urlPresentations.isEmpty)
        #expect(fixture.textView.urlPresentations.allSatisfy { $0.fold == nil })

        fixture.textView.foldsURLs = true
        #expect(abs(fixture.width(of: url) - folded) < 0.5)
        #expect(fixture.hiddenCount(in: url) > 0)
    }

    // MARK: - AC-6

    @Test("AC-6: URL の中にカーソルを置くと全文の幅に戻り、離れると畳む")
    func caretInsideOpensAndLeavingFolds() {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.long)
        let folded = fixture.width(of: url)
        #expect(folded < plain.width(of: url) - 20)

        fixture.textView.setSelectedRange(NSRange(location: url.location + 20, length: 0))
        #expect(isSame(fixture.rect(of: url), plain.rect(of: url)))
        #expect(isUnfolded(fixture, url))

        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(abs(fixture.width(of: url) - folded) < 0.5)

        fixture.textView.setSelectedRange(NSRange(location: NSMaxRange(url), length: 0))
        #expect(isUnfolded(fixture, url))
        fixture.textView.setSelectedRange(NSRange(location: url.location, length: 0))
        #expect(isUnfolded(fixture, url))
    }

    @Test("AC-6: ドラッグで選択している途中は変わらず、URL をまたいだ選択の確定でも畳んだまま")
    func draggingAndSelectionAcrossKeepFold() {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        let folded = fixture.width(of: url)
        let inside = NSRange(location: url.location + 5, length: 3)

        fixture.textView.setSelectedRanges([NSValue(range: inside)], affinity: .downstream, stillSelecting: true)
        #expect(fixture.hiddenCount(in: url) > 0)
        #expect(abs(fixture.width(of: url) - folded) < 0.5)

        fixture.textView.setSelectedRanges([NSValue(range: inside)], affinity: .downstream, stillSelecting: false)
        #expect(isUnfolded(fixture, url))

        let across = NSRange(location: 0, length: (Self.sample as NSString).length)
        fixture.textView.setSelectedRanges([NSValue(range: across)], affinity: .downstream, stillSelecting: false)
        #expect(fixture.hiddenCount(in: url) > 0)
        #expect(abs(fixture.width(of: url) - folded) < 0.5)
    }

    @Test("AC-6: 同じ位置に同じ URL がある別の文章に入れ替えても、負の字間が付いて幅は全文より狭い")
    func replacingStringKeepsFoldWithSameURL() throws {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.long)
        let before = fixture.hiddenCount(in: url)
        #expect(before > 0)

        fixture.textView.string = "前置き\n\(Self.short)\nと\n\(Self.long)\n別の後書きです"
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let hidden = try #require((url.location..<NSMaxRange(url)).first { fixture.isHidden(at: $0) })
        #expect((fixture.kern(at: hidden) ?? 0) < 0)
        #expect(fixture.hiddenCount(in: url) == before)
        #expect(fixture.width(of: url) < plain.width(of: url) - 20)
    }

    // MARK: - AC-7

    @Test("AC-7: URL の末尾で打ち続けている間は畳まず、その後に打った文字は字間がふつう")
    func typingAtURLEndDoesNotFold() {
        let text = "前置き \(Self.long)"
        let fixture = FoldFixture(text, selection: NSRange(location: (text as NSString).length, length: 0))
        let url = fixture.range(of: Self.long)
        #expect(isUnfolded(fixture, url))

        fixture.insert("x")
        let extended = fixture.range(of: Self.long + "x")
        #expect(extended.location != NSNotFound)
        #expect(isUnfolded(fixture, extended))
        #expect(fixture.textView.typingAttributes[.editorURLHidden] == nil)

        fixture.insert(" 続き")
        let tail = fixture.range(of: " 続き")
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long + "x")) > 0)
        for location in tail.location..<NSMaxRange(tail) {
            #expect(!fixture.isHidden(at: location))
            #expect(fixture.kern(at: location) == layout.kern)
        }
    }

    @Test("AC-7: URL を貼り付けた直後は畳まず、その後に打った文字は字間がふつう")
    func pastedURLIsNotFoldedRightAway() {
        let fixture = FoldFixture("")
        fixture.insert(Self.long)
        let url = fixture.range(of: Self.long)
        #expect(isUnfolded(fixture, url))
        #expect(fixture.textView.string == Self.long)

        fixture.insert(" あとで")
        let tail = fixture.range(of: " あとで")
        for location in tail.location..<NSMaxRange(tail) {
            #expect(!fixture.isHidden(at: location))
            #expect(fixture.kern(at: location) == layout.kern)
        }
    }

    @Test("AC-7: URL の外で打った文字は隠す字間・印が付かずふつうの幅")
    func typingOutsideURLIsPlain() {
        let fixture = FoldFixture(Self.sample)
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.insert("あ")

        #expect(!fixture.isHidden(at: 0))
        #expect(fixture.kern(at: 0) == layout.kern)
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) > 0)
        #expect(fixture.textView.typingAttributes[.editorURLHidden] == nil)
        #expect(fixture.textView.typingAttributes[.ligature] == nil)
    }

    // MARK: - AC-8

    @Test("AC-8: 畳む・開くは取り消しの履歴を増やさず、⌘Z は直前の文章の編集を取り消す")
    func foldingDoesNotAddUndoSteps() {
        let fixture = FoldFixture("前置き ", undo: true)
        let textView = fixture.textView

        fixture.type("追記", at: NSRange(location: 0, length: 0))
        fixture.type(Self.long, at: NSRange(location: (textView.string as NSString).length, length: 0))
        let url = fixture.range(of: Self.long)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(fixture.hiddenCount(in: url) > 0)
        textView.setSelectedRange(NSRange(location: url.location + 10, length: 0))
        #expect(isUnfolded(fixture, url))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(fixture.hiddenCount(in: url) > 0)

        fixture.undoManager.undo()
        #expect(textView.string == "追記前置き ")
        fixture.undoManager.undo()
        #expect(textView.string == "前置き ")
        #expect(!fixture.undoManager.canUndo)
        #expect(fixture.undoManager.canRedo)
    }

    // MARK: - AC-9

    @Test("AC-9: 変換中は畳む・開くを付け直さず、確定した後に付け直す")
    func markedTextDefersFolding() {
        let fixture = FoldFixture(Self.sample)
        let textView = fixture.textView
        let url = fixture.range(of: Self.long)
        let hiddenBefore = fixture.hiddenCount(in: url)
        #expect(hiddenBefore > 0)

        textView.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: noReplacement)
        #expect(textView.hasMarkedText())
        #expect(textView.string.hasPrefix("にほ"))

        textView.foldsURLs = false
        #expect(textView.hasMarkedText())
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) == hiddenBefore)
        #expect(!textView.urlPresentations.isEmpty)

        textView.unmarkText()
        #expect(!textView.hasMarkedText())
        #expect(textView.string.hasPrefix("にほ"))
        #expect(fixture.hiddenCount(in: fixture.range(of: Self.long)) == 0)
        #expect(textView.urlPresentations.allSatisfy { $0.fold == nil })
    }

    @Test("AC-9: URL より前で変換しても、「…」は畳んだ URL の中の同じ文字に描かれる")
    func ellipsisFollowsItsCharacterWhileMarkedTextIsBeforeTheURL() throws {
        let fixture = FoldFixture(Self.sample)
        let textView = fixture.textView
        let storage = fixture.storage

        func ellipsisLocations() -> [Int] {
            (0..<storage.length).filter { storage.attribute(.editorURLEllipsis, at: $0, effectiveRange: nil) != nil }
        }

        let before = try #require(ellipsisLocations().first)
        #expect(ellipsisLocations().count == 1)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText("にほんご", selectedRange: NSRange(location: 4, length: 0), replacementRange: noReplacement)
        #expect(textView.hasMarkedText())

        let after = try #require(ellipsisLocations().first)
        #expect(ellipsisLocations().count == 1)
        #expect(after == before + 4)

        let url = fixture.range(of: Self.long)
        let urlRect = fixture.rect(of: url)
        let characterRect = fixture.rect(of: NSRange(location: after, length: 1))
        let ellipsis = try #require(textView.urlEllipsisRects().first)
        #expect(textView.urlEllipsisRects().count == 1)
        #expect(ellipsis.minX >= urlRect.minX)
        #expect(ellipsis.minX < urlRect.maxX)
        #expect(abs(ellipsis.minX - characterRect.minX) < 0.5)
        #expect(abs(ellipsis.minY - characterRect.minY) < characterRect.height)
    }

    // MARK: - AC-26

    @Test("AC-26: 畳んだ URL の次の行で変換を始めた直後のカーソルと今いる行のハイライトは、配置を確定した後の位置と同じ")
    func caretAfterFoldedURLIsSettledWhenMarkedTextStarts() throws {
        var readability = FoldFixture.readability
        readability.highlightsCurrentLine = true
        let text = "\(FoldFixture.wrappingURL)\n後書き"
        let lineStart = (text as NSString).length - 3
        let fixture = FoldFixture(text, readability: readability, selection: NSRange(location: lineStart, length: 0))
        let opened = FoldFixture(text, readability: readability, foldsURLs: false)
        let urlRange = fixture.range(of: FoldFixture.wrappingURL)
        let foldedHeight = FindHighlighter.rects(for: urlRange, in: fixture.textView).reduce(0) { $0 + $1.height }
        let openedHeight = FindHighlighter.rects(for: urlRange, in: opened.textView).reduce(0) { $0 + $1.height }
        #expect(foldedHeight < openedHeight)
        let textView = fixture.textView
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let urlEnd = try #require(contentManager.location(contentManager.documentRange.location, offsetBy: lineStart - 1))
        let urlParagraph = try #require(NSTextRange(location: contentManager.documentRange.location, end: urlEnd))
        layoutManager.invalidateLayout(for: urlParagraph)

        textView.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: noReplacement)
        #expect(textView.hasMarkedText())
        let started = try #require(textView.caretView?.caretRect)
        let startedHighlight = try #require(textView.currentLineHighlightRect)

        layoutManager.ensureLayout(for: layoutManager.documentRange)
        textView.refreshCaret()
        let settled = try #require(textView.caretView?.caretRect)
        let settledHighlight = try #require(textView.currentLineHighlightRect)

        #expect(abs(started.minY - settled.minY) < 0.5)
        #expect(abs(started.minX - settled.minX) < 0.5)
        #expect(abs(startedHighlight.minY - settledHighlight.minY) < 0.5)
        #expect(abs(startedHighlight.height - settledHighlight.height) < 0.5)
    }

    @Test("AC-9: 変換中でない間は、設定を変えるとすぐ付け直される")
    func foldsRefreshImmediatelyWithoutMarkedText() {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        fixture.textView.foldsURLs = false
        #expect(fixture.hiddenCount(in: url) == 0)
        fixture.textView.foldsURLs = true
        #expect(fixture.hiddenCount(in: url) > 0)
    }

    // MARK: - AC-10

    @Test("AC-10: URL 以外の文字と開いた URL の段落スタイルと字間は設定の値のまま")
    func otherTextKeepsParagraphStyleAndKern() {
        let text = "前置き \(Self.long) 後書き\n- 箇条書きの項目です"
        let url = (text as NSString).range(of: Self.long)
        let fixture = FoldFixture(text, selection: NSRange(location: url.location + 3, length: 0))

        func expectStyled(_ label: String, hiddenAllowed: Bool) {
            let hidden = hiddenAllowed ? Set((url.location..<NSMaxRange(url)).filter { fixture.isHidden(at: $0) }) : []
            for location in 0..<(text as NSString).length where !hidden.contains(location) {
                #expect(fixture.kern(at: location) == layout.kern, "\(label): 字間 \(location)")
                let style = fixture.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
                #expect(style?.lineSpacing == layout.lineSpacing, "\(label): 行間 \(location)")
                #expect(style?.paragraphSpacing == layout.paragraphSpacing, "\(label): 段落の間隔 \(location)")
            }
        }

        expectStyled("開く", hiddenAllowed: false)
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(fixture.hiddenCount(in: url) > 0)
        expectStyled("畳む", hiddenAllowed: true)

        let bullet = fixture.range(of: "- 箇条書き")
        let style = fixture.storage.attribute(.paragraphStyle, at: bullet.location, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.headIndent ?? 0) > 0)
    }

    @Test("AC-10: URL が無い文章の段落の属性は、設定オフのときと同じ")
    func textWithoutURLMatchesUnfoldedAttributes() {
        let text = "ふつうの文章です\n- 箇条書きの項目\nhttp:// だけ"
        let folded = FoldFixture(text)
        let plain = FoldFixture(text, foldsURLs: false)

        for location in 0..<(text as NSString).length {
            #expect(folded.kern(at: location) == plain.kern(at: location))
            let first = folded.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let second = plain.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            #expect(first == second)
            #expect(!folded.isHidden(at: location))
        }
    }

    // MARK: - AC-23

    @Test("AC-23: 開いた後・畳んだ後のカーソルと今いる行のハイライトは、その配置での位置になる")
    func caretAndLineHighlightFollowFolding() throws {
        var readability = FoldFixture.readability
        readability.highlightsCurrentLine = true
        let text = "先頭\n\(FoldFixture.wrappingURL) 後書き\n最後の行です"
        let lastLine = (text as NSString).range(of: "最後の行です").location
        let urlLocation = (text as NSString).range(of: FoldFixture.wrappingURL).location
        let inside = NSRange(location: urlLocation + 100, length: 0)
        let atLast = NSRange(location: lastLine, length: 0)

        let fixture = FoldFixture(text, readability: readability, selection: atLast)
        let url = fixture.range(of: FoldFixture.wrappingURL)
        let opened = FoldFixture(text, readability: readability, foldsURLs: false, selection: inside)
        let settled = FoldFixture(text, readability: readability, selection: atLast)
        #expect(FindHighlighter.rects(for: url, in: opened.textView).count >= 2)

        let foldedHighlight = try #require(fixture.textView.currentLineHighlightRect)
        let settledHighlight = try #require(settled.textView.currentLineHighlightRect)
        #expect(foldedHighlight == settledHighlight)

        fixture.textView.setSelectedRange(inside)
        #expect(fixture.hiddenCount(in: url) == 0)
        let openCaret = try #require(fixture.textView.caretView?.caretRect)
        let openHighlight = try #require(fixture.textView.currentLineHighlightRect)
        #expect(openCaret == opened.textView.caretView?.caretRect)
        #expect(openHighlight == opened.textView.currentLineHighlightRect)
        fixture.textView.refreshCaret()
        #expect(fixture.textView.caretView?.caretRect == openCaret)
        #expect(fixture.textView.currentLineHighlightRect == openHighlight)

        fixture.textView.setSelectedRange(atLast)
        #expect(fixture.hiddenCount(in: url) > 0)
        let foldedCaret = try #require(fixture.textView.caretView?.caretRect)
        let highlight = try #require(fixture.textView.currentLineHighlightRect)
        #expect(highlight == settledHighlight)
        #expect(foldedCaret == settled.textView.caretView?.caretRect)
        fixture.textView.refreshCaret()
        #expect(fixture.textView.caretView?.caretRect == foldedCaret)
        #expect(fixture.textView.currentLineHighlightRect == highlight)
        #expect(foldedCaret != openCaret)
    }

    // MARK: - AC-24

    @Test("AC-24: 文字の大きさを変えると、隠す字間が新しいフォントの幅で付け直される")
    func fontChangeRefreshesHiddenKerns() throws {
        let fixture = FoldFixture(Self.sample)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let url = fixture.range(of: Self.long)
        let newFont = NSFont.systemFont(ofSize: 20)
        let scheme = "https://".count

        fixture.textView.applyFont(newFont)
        plain.textView.applyFont(newFont)

        let newLayout = EditorTextLayout(font: newFont, readability: FoldFixture.readability)
        let expectedFirst = -NSAttributedString(string: "h", attributes: [.font: newFont]).size().width
        #expect(abs((fixture.kern(at: url.location) ?? 0) - expectedFirst) < 0.001)
        #expect(fixture.hiddenCount(in: NSRange(location: url.location, length: scheme)) == scheme)

        let ellipsisKern = try #require(fixture.textView.appliedHiddenKerns.last)
        let width = NSAttributedString(string: "…", attributes: [.font: newFont]).size().width
        let character = (fixture.textView.string as NSString).substring(with: NSRange(location: ellipsisKern.location, length: 1))
        let characterWidth = NSAttributedString(string: character, attributes: [.font: newFont]).size().width
        #expect(abs(ellipsisKern.kern - (-characterWidth + width + newLayout.kern)) < 0.001)
        #expect(fixture.width(of: url) < plain.width(of: url) - 20)
        #expect(fixture.textView.urlPresentations.contains { $0.fold != nil })
    }

    @Test("AC-24: 字間の設定を変えると、「…」を描く文字の字間が新しい字間を足した値になり、幅は全文より狭い")
    func letterSpacingChangeRefreshesHiddenKerns() throws {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        var changed = FoldFixture.readability
        changed.letterSpacingPercent = 30

        fixture.textView.applyReadability(changed)
        let plain = FoldFixture(Self.sample, readability: changed, foldsURLs: false)

        let newLayout = EditorTextLayout(font: FoldFixture.font, readability: changed)
        let last = try #require(fixture.textView.appliedHiddenKerns.last)
        let character = (fixture.textView.string as NSString).substring(with: NSRange(location: last.location, length: 1))
        let characterWidth = NSAttributedString(string: character, attributes: [.font: FoldFixture.font]).size().width
        let ellipsisWidth = NSAttributedString(string: "…", attributes: [.font: FoldFixture.font]).size().width
        #expect(abs(last.kern - (-characterWidth + ellipsisWidth + newLayout.kern)) < 0.001)
        #expect(fixture.kern(at: last.location) == last.kern)
        #expect(fixture.width(of: url) < plain.width(of: url) - 20)

        let outside = fixture.range(of: "前置き")
        #expect(fixture.kern(at: outside.location) == newLayout.kern)
    }
}
