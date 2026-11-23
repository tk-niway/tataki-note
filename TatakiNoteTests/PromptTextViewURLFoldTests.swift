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
    static let wrappingJapaneseText = String(repeating: "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。", count: 6)
    static let wrappingEnglishText = String(
        repeating: "The quick brown fox jumps over the lazy dog while the sun sets slowly behind the hills. ",
        count: 4
    )

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

    func hasEllipsis(at location: Int) -> Bool {
        storage.attribute(.editorURLEllipsis, at: location, effectiveRange: nil) != nil
    }

    func hasLinkIcon(at location: Int) -> Bool {
        storage.attribute(.editorURLLinkIcon, at: location, effectiveRange: nil) != nil
    }

    func ligature(at location: Int) -> Int? {
        (storage.attribute(.ligature, at: location, effectiveRange: nil) as? NSNumber)?.intValue
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
private final class ColorProbe {
    enum Kind: String, Equatable {
        case none
        case clear
        case url
        case other
    }

    static let text = "前の段落\n" + FoldFixture.longURL + " end"

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let urlRange: NSRange

    init?() {
        textView.isRichText = false
        textView.font = FoldFixture.font
        textView.string = Self.text
        urlRange = (Self.text as NSString).range(of: FoldFixture.longURL)
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return nil }
        func textRange(_ range: NSRange) -> NSTextRange? {
            let start = contentManager.documentRange.location
            guard let lower = contentManager.location(start, offsetBy: range.location),
                  let upper = contentManager.location(lower, offsetBy: range.length)
            else { return nil }
            return NSTextRange(location: lower, end: upper)
        }
        let hidden = [
            NSRange(location: urlRange.location, length: 8),
            NSRange(location: urlRange.location + 20, length: 6),
        ]
        guard let urlTextRange = textRange(urlRange) else { return nil }
        layoutManager.addRenderingAttribute(.foregroundColor, value: EditorURLFoldStyler.urlColor, for: urlTextRange)
        for range in hidden {
            guard let hiddenRange = textRange(range) else { return nil }
            layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.clear, for: hiddenRange)
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
    }

    func kind(at location: Int) -> Kind {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: location)
        else { return .other }
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) {
                color = attributes[.foregroundColor] as? NSColor
            }
            return false
        }
        guard let color else { return .none }
        if color.alphaComponent == 0 { return .clear }
        if color == EditorURLFoldStyler.urlColor { return .url }
        return .other
    }

    func kinds(in range: Range<Int>) -> [Kind] {
        range.map { kind(at: $0) }
    }

    func replace(_ range: NSRange, with string: String) {
        textView.textStorage?.replaceCharacters(in: range, with: string)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
    }

    func outcome(at location: Int, moved: Kind, stayed: Kind) -> String {
        let actual = kind(at: location)
        if actual == moved { return "動いた" }
        if actual == stayed { return "残った" }
        return "消えた(\(actual.rawValue))"
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

    // MARK: - AC-35

    @Test(
        "AC-35: 数行に折り返す段落の末尾で改行した直後と続けて1文字打った直後のカーソルと今いる行のハイライトは、配置を確定した後の位置と同じ",
        arguments: [
            ("畳んだ URL", "\(FoldFixture.wrappingURL) を見る", true),
            ("設定オフの長い URL", "\(FoldFixture.wrappingURL) を見る", false),
            ("長い日本語の文章", FoldFixture.wrappingJapaneseText, true),
            ("長い英文", FoldFixture.wrappingEnglishText, true),
        ]
    )
    func caretIsSettledWhenTextChanges(kind: String, text: String, foldsURLs: Bool) throws {
        var readability = FoldFixture.readability
        readability.highlightsCurrentLine = true
        let fixture = FoldFixture(
            text,
            readability: readability,
            foldsURLs: foldsURLs,
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        let textView = fixture.textView
        let layoutManager = try #require(textView.textLayoutManager)
        let urlRange = fixture.range(of: FoldFixture.wrappingURL)

        let isFolded = urlRange.location != NSNotFound && fixture.kern(at: urlRange.location + 1).map { $0 < 0 } == true
        #expect(isFolded == (foldsURLs && urlRange.location != NSNotFound), Comment(rawValue: kind))
        if !isFolded {
            let paragraph = NSRange(location: 0, length: (text as NSString).length)
            let paragraphRects = FindHighlighter.rects(for: paragraph, in: textView)
            let lineHeight = try #require(paragraphRects.map(\.height).min())
            #expect(paragraphRects.reduce(0) { $0 + $1.height } >= lineHeight * 2, Comment(rawValue: kind))
        }

        func expectSettled(_ label: String) throws {
            let label = "\(kind): \(label)"
            let started = try #require(textView.caretView?.caretRect)
            let startedHighlight = try #require(textView.currentLineHighlightRect)
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            textView.refreshCaret()
            let settled = try #require(textView.caretView?.caretRect)
            let settledHighlight = try #require(textView.currentLineHighlightRect)
            #expect(abs(started.minY - settled.minY) < 0.5, Comment(rawValue: label))
            #expect(abs(started.minX - settled.minX) < 0.5, Comment(rawValue: label))
            #expect(abs(startedHighlight.minY - settledHighlight.minY) < 0.5, Comment(rawValue: label))
            #expect(abs(startedHighlight.height - settledHighlight.height) < 0.5, Comment(rawValue: label))
        }

        textView.insertText("\n", replacementRange: textView.selectedRange())
        try expectSettled("改行の直後")

        textView.insertText("a", replacementRange: textView.selectedRange())
        try expectSettled("1文字の直後")
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

    // MARK: - AC-32

    private static let iconOffset = "https://".count - 1

    private func slashWidth(_ font: NSFont) -> CGFloat {
        NSAttributedString(string: "/", attributes: [.font: font]).size().width
    }

    @Test("AC-32: 畳んだ URL の先頭にアイコンの矩形が1つあり、URL の左端の近くで URL の行の中にある")
    func foldedURLHasLinkIconAtItsLeftEdge() throws {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        let urlRect = fixture.rect(of: url)

        let icons = fixture.textView.urlLinkIconRects()
        #expect(icons.count == 1)
        let icon = try #require(icons.first)
        #expect(icon.minX >= urlRect.minX - 0.5)
        #expect(icon.minX < urlRect.minX + FoldFixture.font.pointSize / 2)
        #expect(icon.maxY > urlRect.minY)
        #expect(icon.minY < urlRect.maxY)
        #expect(fixture.textView.string == Self.sample)
    }

    @Test("AC-32: ドメインの文字は、アイコンの幅とすき間の分だけ後ろから始まる")
    func domainStartsAfterTheIconAndGap() throws {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        let plain = FoldFixture(Self.sample, foldsURLs: false)
        let urlRect = fixture.rect(of: url)
        let size = try #require(EditorURLLinkIcon.size(pointSize: FoldFixture.font.pointSize))
        let gap = EditorURLLinkIcon.gap(pointSize: FoldFixture.font.pointSize)

        let domainStart = url.location + "https://".count
        let foldedThird = fixture.rect(of: NSRange(location: domainStart + 1, length: 1))
        let plainFirst = plain.rect(of: NSRange(location: domainStart, length: 1))
        let plainThird = plain.rect(of: NSRange(location: domainStart + 1, length: 1))
        let expected = size.width + gap + (plainThird.minX - plainFirst.minX)
        #expect(abs((foldedThird.minX - urlRect.minX) - expected) < 1.5)
    }

    @Test("AC-32: アイコンの文字の字間は、その文字の幅の負の値にアイコンの幅とすき間を足した値")
    func linkIconKernLeavesRoomForIconAndGap() throws {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)

        let size = try #require(EditorURLLinkIcon.size(pointSize: FoldFixture.font.pointSize))
        let gap = EditorURLLinkIcon.gap(pointSize: FoldFixture.font.pointSize)
        let expectedKern = -slashWidth(FoldFixture.font) + size.width + gap
        let kern = try #require(fixture.kern(at: url.location + Self.iconOffset))
        #expect(abs(kern - expectedKern) < 0.01)
    }

    @Test("AC-32: カーソルが触れて開いた URL・一致で開いた URL・短い URL だけの文章・設定オフにはアイコンが無く、字間は設定の値に戻る")
    func noLinkIconWhenOpenedShortOrOff() {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        let iconLocation = url.location + Self.iconOffset
        #expect(fixture.textView.urlLinkIconRects().count == 1)

        fixture.textView.setSelectedRange(NSRange(location: url.location + 20, length: 0))
        #expect(fixture.textView.urlLinkIconRects().isEmpty)
        #expect(fixture.kern(at: iconLocation) == layout.kern)

        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(fixture.textView.urlLinkIconRects().count == 1)

        let match = NSRange(location: url.location + 20, length: 4)
        fixture.textView.showFindHighlights([match], current: match)
        #expect(fixture.textView.urlLinkIconRects().isEmpty)
        #expect(fixture.kern(at: iconLocation) == layout.kern)
        fixture.textView.showFindHighlights([], current: nil)
        #expect(fixture.textView.urlLinkIconRects().count == 1)

        let shortOnly = FoldFixture("前置き\n\(Self.short)\n後書き")
        #expect(shortOnly.textView.urlLinkIconRects().isEmpty)

        let off = FoldFixture(Self.sample, foldsURLs: false)
        #expect(off.textView.urlLinkIconRects().isEmpty)
        #expect(off.kern(at: iconLocation) == layout.kern)
    }

    @Test("AC-32: 文字の大きさを変えると、アイコンの字間が新しいフォントサイズのアイコンの幅とすき間で付け直される")
    func fontChangeRefreshesLinkIconKern() throws {
        let fixture = FoldFixture(Self.sample)
        let url = fixture.range(of: Self.long)
        let before = try #require(fixture.textView.urlLinkIconRects().first)
        let newFont = NSFont.systemFont(ofSize: 20)

        fixture.textView.applyFont(newFont)

        let size = try #require(EditorURLLinkIcon.size(pointSize: 20))
        let expectedKern = -slashWidth(newFont) + size.width + EditorURLLinkIcon.gap(pointSize: 20)
        let kern = try #require(fixture.kern(at: url.location + Self.iconOffset))
        #expect(abs(kern - expectedKern) < 0.01)
        let after = try #require(fixture.textView.urlLinkIconRects().first)
        #expect(after.height > before.height)
    }

    // MARK: - 新しく作った入力欄との比べ

    private static let multi = "冒頭の段落\n\(long)\n中ほどの段落です\nhttps://example.com/docs/2026/11/another-long-page-name/with/more\n途中 \(long)/x を見る\n末尾の段落"

    private static let longDocument: String = (0..<200).map { number in
        number % 5 == 0
            ? "段落 \(number) の本文 https://example.com/docs/2026/11/page-\(number)-some-long-title"
            : "段落 \(number) の本文です"
    }.joined(separator: "\n")

    private func ensureLayout(_ fixture: FoldFixture) {
        if let layoutManager = fixture.textView.textLayoutManager {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
    }

    private func colorName(_ color: NSColor?) -> String {
        guard let color else { return "なし" }
        if color.alphaComponent == 0 { return "透明" }
        return color == EditorURLFoldStyler.urlColor ? "URL" : "他"
    }

    private func rectsDiffer(_ first: [CGRect], _ second: [CGRect]) -> Bool {
        first.count != second.count || zip(first, second).contains { !isSame($0, $1) }
    }

    private func mismatches(_ fixture: FoldFixture, comparesCaret: Bool = false) -> [String] {
        let textView = fixture.textView
        let caret = textView.caretView?.caretRect
        let fresh = FoldFixture(
            textView.string,
            readability: textView.readability,
            foldsURLs: textView.foldsURLs,
            selection: textView.selectedRange()
        )
        ensureLayout(fixture)
        ensureLayout(fresh)
        var found: [String] = []
        for location in 0..<(textView.string as NSString).length {
            if fixture.isHidden(at: location) != fresh.isHidden(at: location) { found.append("隠す印 \(location)") }
            if fixture.hasEllipsis(at: location) != fresh.hasEllipsis(at: location) { found.append("「…」の印 \(location)") }
            if fixture.hasLinkIcon(at: location) != fresh.hasLinkIcon(at: location) { found.append("アイコンの印 \(location)") }
            if fixture.ligature(at: location) != fresh.ligature(at: location) { found.append("合字 \(location)") }
            let kernDiffers: Bool
            switch (fixture.kern(at: location), fresh.kern(at: location)) {
            case (nil, nil): kernDiffers = false
            case let (first?, second?): kernDiffers = abs(first - second) > 0.01
            default: kernDiffers = true
            }
            if kernDiffers { found.append("字間 \(location)") }
            let first = colorName(fixture.renderedColor(at: location))
            let second = colorName(fresh.renderedColor(at: location))
            if first != second { found.append("色 \(location): \(first) と \(second)") }
        }
        if rectsDiffer(textView.urlEllipsisRects(), fresh.textView.urlEllipsisRects()) { found.append("「…」の矩形") }
        if rectsDiffer(textView.urlLinkIconRects(), fresh.textView.urlLinkIconRects()) { found.append("アイコンの矩形") }
        if comparesCaret {
            switch (caret, fresh.textView.caretView?.caretRect) {
            case let (first?, second?): if !isSame(first, second) { found.append("カーソルの位置") }
            case (nil, nil): break
            default: found.append("カーソルの位置")
            }
        }
        return found
    }

    private func expectMatchesFresh(_ fixture: FoldFixture, _ label: String, comparesCaret: Bool = false) {
        let found = mismatches(fixture, comparesCaret: comparesCaret)
        #expect(found.isEmpty, Comment(rawValue: "\(label): \(found.prefix(8).joined(separator: ", "))"))
    }

    // MARK: - AC-6

    private func expectAwayEdit(_ label: String, _ operation: (FoldFixture) -> Void) {
        let fixture = FoldFixture(Self.multi, selection: NSRange(location: 1, length: 0))
        operation(fixture)
        expectMatchesFresh(fixture, label)
    }

    @Test("AC-6: URL から離れた所で打つと、新しく作った入力欄と同じ")
    func typingAwayFromURLsMatchesAFreshEditor() {
        expectAwayEdit("打つ") { $0.type("あ", at: NSRange(location: 1, length: 0)) }
    }

    @Test("AC-6: URL から離れた所で改行すると、新しく作った入力欄と同じ")
    func newlineAwayFromURLsMatchesAFreshEditor() {
        expectAwayEdit("改行する") { $0.type("\n", at: NSRange(location: 1, length: 0)) }
    }

    @Test("AC-6: URL から離れた所で確定すると、新しく作った入力欄と同じ")
    func insertingAwayFromURLsMatchesAFreshEditor() {
        expectAwayEdit("確定する") { $0.insert("確定") }
        expectAwayEdit("改行を確定する") { $0.insert("\n") }
    }

    @Test("AC-6: URL から離れた最後の段落で打つと、新しく作った入力欄と同じ")
    func typingInLastParagraphMatchesAFreshEditor() {
        let end = (Self.multi as NSString).length
        expectAwayEdit("最後の段落で打つ") { $0.type("あ", at: NSRange(location: end - 3, length: 0)) }
    }

    @Test("AC-6: URL から離れた所で続けて打つと、新しく作った入力欄と同じ")
    func typingRepeatedlyAwayFromURLsMatchesAFreshEditor() {
        expectAwayEdit("続けて打つ") {
            $0.type("あ", at: NSRange(location: 1, length: 0))
            $0.type("い", at: NSRange(location: 2, length: 0))
            $0.insert("う")
        }
    }

    @Test("AC-6: 設定オフでは、打っても印・負の字間・色が付かない")
    func editsWithFoldingOffAddNoMarks() {
        let fixture = FoldFixture(Self.multi, foldsURLs: false, selection: NSRange(location: 1, length: 0))
        fixture.type("あ", at: NSRange(location: 1, length: 0))
        fixture.insert("\n")
        fixture.insert("確定")

        for location in 0..<(fixture.textView.string as NSString).length {
            #expect(!fixture.isHidden(at: location))
            #expect(fixture.kern(at: location) == layout.kern)
            #expect(fixture.renderedColor(at: location) == nil)
        }
        #expect(fixture.textView.urlEllipsisRects().isEmpty)
        #expect(fixture.textView.urlLinkIconRects().isEmpty)
        #expect(fixture.textView.urlPresentations.count == 3)
        #expect(fixture.textView.urlPresentations.allSatisfy { $0.fold == nil })
        expectMatchesFresh(fixture, "設定オフ")
    }

    // MARK: - AC-7

    @Test("AC-7: URL に触れる変更・置換・入れ替え・設定の切り替えの後も、新しく作った入力欄と同じ")
    func editsTouchingURLsMatchAFreshEditor() {
        let url = NSRange(location: (Self.multi as NSString).range(of: Self.long).location, length: (Self.long as NSString).length)
        let urlEnd = NSMaxRange(url)
        let paragraphEnd = (Self.multi as NSString).range(of: "中ほどの段落です").location + 8
        var wider = FoldFixture.readability
        wider.letterSpacingPercent = 30
        let operations: [(String, (FoldFixture) -> Void)] = [
            ("URL の末尾で打つ", { $0.type("x", at: NSRange(location: urlEnd, length: 0)) }),
            ("URL の末尾で確定する", {
                $0.textView.setSelectedRange(NSRange(location: urlEnd, length: 0))
                $0.insert("x")
            }),
            ("URL の中で打つ", { $0.type("x", at: NSRange(location: url.location + 10, length: 0)) }),
            ("URL の直前で英字を打つ", { $0.type("a", at: NSRange(location: url.location, length: 0)) }),
            ("URL の直後に空白を打つ", { $0.type(" ", at: NSRange(location: urlEnd, length: 0)) }),
            ("URL の直後で改行して打つ", {
                $0.textView.setSelectedRange(NSRange(location: urlEnd, length: 0))
                $0.insert("\n")
                $0.insert("あ")
            }),
            ("URL を貼る", {
                $0.textView.setSelectedRange(NSRange(location: paragraphEnd, length: 0))
                $0.insert(" " + Self.long + "/pasted")
            }),
            ("URL の段落をつなぐ", { $0.type("", at: NSRange(location: url.location - 1, length: 1)) }),
            ("URL の段落を分ける", { $0.type("\n", at: NSRange(location: url.location + 5, length: 0)) }),
            ("段落の始まりで打つ", { $0.type("あ", at: NSRange(location: urlEnd + 1, length: 0)) }),
            ("URL を消す", { $0.type("", at: url) }),
            ("置換", {
                let text = $0.textView.string as NSString
                $0.textView.replaceForFind(
                    [
                        FindEdit(range: text.range(of: "中ほど"), replacement: "真ん中の"),
                        FindEdit(range: NSRange(location: url.location + 20, length: 4), replacement: "XYZWV"),
                    ],
                    selectionAfter: NSRange(location: 0, length: 0)
                )
            }),
            ("文章の入れ替え", {
                $0.textView.string = "別の文章\n\(Self.long)/changed\n後書き"
                $0.textView.setSelectedRange(NSRange(location: 0, length: 0))
            }),
            ("設定をオフにする", { $0.textView.foldsURLs = false }),
            ("設定をオフにしてオンに戻す", {
                $0.textView.foldsURLs = false
                $0.textView.foldsURLs = true
            }),
            ("字間の設定を変える", { $0.textView.applyReadability(wider) }),
        ]
        for (label, operation) in operations {
            let fixture = FoldFixture(Self.multi, selection: NSRange(location: 1, length: 0))
            operation(fixture)
            expectMatchesFresh(fixture, label, comparesCaret: label.contains("直後で改行"))
        }
    }

    @Test("AC-7: 取り消し・やり直しの後も、新しく作った入力欄と同じ")
    func undoAndRedoMatchAFreshEditor() {
        let url = (Self.multi as NSString).range(of: Self.long)
        let edits: [(String, NSRange, String)] = [
            ("URL の末尾で打つ", NSRange(location: NSMaxRange(url), length: 0), "x"),
            ("URL を消す", url, ""),
            ("段落をつなぐ", NSRange(location: url.location - 1, length: 1), ""),
        ]
        for (label, range, replacement) in edits {
            let fixture = FoldFixture(Self.multi, selection: NSRange(location: 1, length: 0), undo: true)
            fixture.type(replacement, at: range)
            expectMatchesFresh(fixture, "\(label)の後")
            fixture.undoManager.undo()
            #expect(fixture.textView.string == Self.multi)
            expectMatchesFresh(fixture, "\(label)を取り消した後")
            fixture.undoManager.redo()
            expectMatchesFresh(fixture, "\(label)をやり直した後")
        }
    }

    // MARK: - AC-8

    @Test("AC-8: 200 段落・URL 40 個の文章で URL の無い段落に1文字打つと、付け直すのはその段落だけ")
    func typingInURLFreeParagraphRestylesOnlyThatParagraph() throws {
        let fixture = FoldFixture(Self.longDocument)
        let textView = fixture.textView
        #expect(textView.urlPresentations.count == 40)
        let target = fixture.range(of: "段落 101 の本文です")
        try #require(target.location != NSNotFound)
        let location = target.location + 4

        for label in ["shouldChangeText", "insertText"] {
            let before = (textView.string as NSString).length
            if label == "insertText" {
                textView.setSelectedRange(NSRange(location: location, length: 0))
                fixture.insert("y")
            } else {
                fixture.type("x", at: NSRange(location: location, length: 0))
            }
            #expect((textView.string as NSString).length == before + 1)
            let paragraph = (textView.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let update = try #require(textView.lastURLFoldUpdate, Comment(rawValue: label))
            #expect(update.redetectedRange == paragraph, Comment(rawValue: label))
            #expect(update.restyleRanges == [paragraph], Comment(rawValue: label))
            let firstRecolor = try #require(update.recolorRanges.first, Comment(rawValue: label))
            #expect(firstRecolor.location >= paragraph.location, Comment(rawValue: label))
            if PromptTextView.urlColorsFollowText {
                #expect(update.recolorRanges == [paragraph], Comment(rawValue: label))
            }
            #expect(textView.urlPresentations.count == 40)
        }
    }

    // MARK: - AC-9

    @Test("AC-9: 1文字打つと見え方の決め直しは1回で、その後カーソルを URL に入れると開き、出すと畳まれる")
    func oneKeystrokeRefreshesOnce() {
        for label in ["shouldChangeText", "insertText"] {
            let fixture = FoldFixture(Self.sample)
            let textView = fixture.textView
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            let before = textView.urlFoldRefreshCount
            if label == "insertText" {
                fixture.insert("あ")
            } else {
                fixture.type("あ", at: NSRange(location: 0, length: 0))
            }
            #expect(textView.urlFoldRefreshCount - before == 1, Comment(rawValue: label))

            let url = fixture.range(of: Self.long)
            #expect(fixture.hiddenCount(in: url) > 0, Comment(rawValue: label))
            textView.setSelectedRange(NSRange(location: url.location + 10, length: 0))
            #expect(fixture.hiddenCount(in: url) == 0, Comment(rawValue: label))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            #expect(fixture.hiddenCount(in: url) > 0, Comment(rawValue: label))
        }
    }

    // MARK: - AC-15

    @Test("AC-15: urlColorsFollowText は、前の段落に文字を入れる・消したときに rendering 属性の色が文字と一緒に動くかの実際の振る舞いと合う")
    func colorsFollowTextConstantMatchesRenderingBehavior() throws {
        let inserting = try #require(ColorProbe())
        let url = inserting.urlRange
        let upperBound = NSMaxRange(url) + 1
        let before = inserting.kinds(in: (url.location - 1)..<upperBound)
        #expect(before.contains(.none) && before.contains(.clear) && before.contains(.url))
        #expect(zip(before, before.dropFirst()).contains { $0 != $1 })

        inserting.replace(NSRange(location: 0, length: 0), with: "x")
        let afterInsert = inserting.kinds(in: url.location..<(NSMaxRange(url) + 2))
        let insertMoved = afterInsert == before
        let insertReport = [
            "URL の終わり: " + inserting.outcome(at: NSMaxRange(url), moved: .url, stayed: .none),
            "URL の始まり: " + inserting.outcome(at: url.location, moved: .none, stayed: .clear),
            "透明と URL の色の境目: " + inserting.outcome(at: url.location + 8, moved: .clear, stayed: .url),
        ].joined(separator: " / ")

        let deleting = try #require(ColorProbe())
        deleting.replace(NSRange(location: 0, length: 1), with: "")
        let afterDelete = deleting.kinds(in: (url.location - 2)..<NSMaxRange(url))
        let deleteMoved = afterDelete == before
        let deleteReport = [
            "URL の終わり: " + deleting.outcome(at: NSMaxRange(url) - 1, moved: .none, stayed: .url),
            "URL の始まり: " + deleting.outcome(at: url.location - 1, moved: .clear, stayed: .none),
            "透明と URL の色の境目: " + deleting.outcome(at: url.location + 7, moved: .url, stayed: .clear),
        ].joined(separator: " / ")

        let follows = insertMoved && deleteMoved
        #expect(
            PromptTextView.urlColorsFollowText == follows,
            Comment(rawValue: "入れる: \(insertReport) | 消す: \(deleteReport)")
        )
    }
}
