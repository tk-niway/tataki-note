import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class CaretFixture {
    static let font = NSFont.systemFont(ofSize: 14)

    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let originalColor: NSColor?

    init(_ text: String = "", readability: EditorReadability = .standard) {
        textView.configurePlainTextEditing(textContainerInset: PanelMetrics.textContainerInset, accessibilityIdentifier: "test")
        textView.baseContainerInset = PanelMetrics.textContainerInset
        textView.caretBlinkPeriods = EditorCaretBlink.Periods(on: 3600, off: 3600)
        originalColor = textView.insertionPointColor
        textView.applyFont(Self.font)
        textView.applyReadability(readability)
        textView.string = text
    }

    var caretRect: CGRect? {
        textView.caretView?.caretRect
    }

    var phase: EditorCaretBlink.Phase? {
        textView.caretView?.blink.phase
    }

    func select(_ location: Int, length: Int = 0) {
        textView.setSelectedRange(NSRange(location: location, length: length))
    }
}

@MainActor
struct PromptTextViewCaretTests {
    private func readability(shape: EditorCaretShape, width: Int) -> EditorReadability {
        var value = EditorReadability.standard
        value.caretShape = shape
        value.caretWidth = width
        return value
    }

    // MARK: - AC-17

    @Test("AC-17: 縦線で太さ 1 のときは、システムのカーソルのままで、自前のカーソルは出ない")
    func thinBarKeepsSystemCaret() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 1))

        #expect(fixture.textView.insertionPointColor == fixture.originalColor)
        #expect(fixture.textView.insertionPointColor != .clear)
        #expect(fixture.textView.caretView?.isHidden ?? true)
        #expect(fixture.caretRect == nil)
    }

    @Test("AC-17: それ以外の形・太さでは、システムのカーソルを消して自前のカーソルを出す")
    func otherShapesUseOwnCaret() {
        let variants = [
            readability(shape: .bar, width: 2),
            readability(shape: .bar, width: 4),
            readability(shape: .block, width: 1),
            readability(shape: .underline, width: 1),
        ]
        for variant in variants {
            let fixture = CaretFixture("あいう", readability: variant)
            fixture.select(1)

            #expect(fixture.textView.insertionPointColor == .clear, "\(variant.caretShape) \(variant.caretWidth)")
            #expect(fixture.textView.caretView?.isHidden == false)
            #expect(fixture.caretRect != nil)
            #expect(fixture.textView.caretView?.shape == variant.caretShape)
        }
    }

    @Test("AC-17: 設定を戻すと、システムのカーソルの色に戻り、自前のカーソルは隠れる")
    func returningToThinBarRestoresSystemCaret() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .block, width: 2))
        #expect(fixture.textView.insertionPointColor == .clear)

        fixture.textView.applyReadability(readability(shape: .bar, width: 1))
        #expect(fixture.textView.insertionPointColor == fixture.originalColor)
        #expect(fixture.textView.caretView?.isHidden == true)
        #expect(fixture.phase == .hidden)

        fixture.textView.applyReadability(readability(shape: .underline, width: 1))
        #expect(fixture.textView.insertionPointColor == .clear)
        #expect(fixture.textView.caretView?.isHidden == false)
    }

    @Test("AC-17: 自前のカーソルは、選択を動かすとその位置に付いていく")
    func caretFollowsSelection() throws {
        let fixture = CaretFixture("あいうえお\nかきくけこ", readability: readability(shape: .bar, width: 2))

        fixture.select(0)
        let start = try #require(fixture.caretRect)
        fixture.select(3)
        let middle = try #require(fixture.caretRect)
        fixture.select(6)
        let nextLine = try #require(fixture.caretRect)

        #expect(middle.minX > start.minX)
        #expect(nextLine.minY > start.minY)
        #expect(nextLine.minX < middle.minX)
        #expect(start.width == 2)
    }

    @Test("AC-17: 自前のカーソルは、選択がある間は出さない")
    func noCaretRectWhileSelecting() {
        let fixture = CaretFixture("あいうえお", readability: readability(shape: .bar, width: 2))
        fixture.select(1, length: 2)
        #expect(fixture.caretRect == nil)
        fixture.select(2)
        #expect(fixture.caretRect != nil)
    }

    @Test("AC-17: 空の入力欄でも、自前のカーソルの位置が取れる")
    func caretRectExistsInEmptyEditor() throws {
        let fixture = CaretFixture("", readability: readability(shape: .bar, width: 2))
        fixture.select(0)

        let rect = try #require(fixture.caretRect)
        #expect(rect.minX >= fixture.textView.textContainerOrigin.x)
        #expect(rect.minY >= fixture.textView.textContainerOrigin.y)
        #expect(rect.height > 0)
    }

    @Test("AC-17: 文章の末尾の改行の後(次の行の頭)でも、自前のカーソルの位置が取れ、前の行の下にある")
    func caretRectExistsAfterTrailingNewline() throws {
        let fixture = CaretFixture("a\n", readability: readability(shape: .bar, width: 2))
        fixture.select(0)
        let firstLine = try #require(fixture.caretRect)

        fixture.select(2)
        let afterNewline = try #require(fixture.caretRect)

        #expect(afterNewline.minY > firstLine.minY)
        #expect(afterNewline.minX == firstLine.minX)
        #expect(afterNewline.height > 0)
    }

    @Test("AC-17: カーソルの位置の枠は、幅 0 でも捨てずに取れる")
    func zeroWidthSegmentIsKept() throws {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 2))
        let atStart = try #require(fixture.textView.caretSegmentRect(at: 0))
        let atEnd = try #require(fixture.textView.caretSegmentRect(at: 3))

        #expect(atStart.height > 0)
        #expect(atEnd.minX > atStart.minX)
    }

    @Test("AC-16: ブロックと下線は、カーソルの位置の文字の幅になり、行末では半角1文字ぶんになる")
    func blockAndUnderlineMatchCharacterWidth() throws {
        let layout = EditorTextLayout(font: CaretFixture.font, readability: readability(shape: .block, width: 2))

        for shape in [EditorCaretShape.block, .underline] {
            let fixture = CaretFixture("あいう\n", readability: readability(shape: shape, width: 2))

            fixture.select(1)
            let onCharacter = try #require(fixture.caretRect)
            #expect(abs(onCharacter.width - layout.fullWidthAdvance) < 1, "\(shape): 文字の上")

            fixture.select(3)
            let atLineEnd = try #require(fixture.caretRect)
            #expect(atLineEnd.width == layout.fullWidthAdvance / 2, "\(shape): 行末")
        }
    }

    // MARK: - AC-18

    @Test("AC-18: 窓に入っていない間は点滅しない")
    func doesNotBlinkWithoutWindow() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 2))
        #expect(fixture.phase == .hidden)
    }

    @Test("AC-18: 窓がキーで入力欄にフォーカスがあり何も選択していなければ点滅し、選択すると消える")
    func blinksOnlyWithoutSelection() {
        let fixture = CaretFixture("あいうえお", readability: readability(shape: .bar, width: 2))
        fixture.select(2)
        #expect(fixture.phase == .hidden)

        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: true)
        #expect(fixture.phase == .on)

        fixture.select(1, length: 2)
        #expect(fixture.phase == .hidden)

        fixture.select(4)
        #expect(fixture.phase == .on)
    }

    @Test("AC-18: 窓がキーでなくなる・フォーカスが外れると消え、戻ると点滅する")
    func stopsBlinkingWhenFocusIsLost() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 2))
        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: true)
        #expect(fixture.phase == .on)

        fixture.textView.setCaretFocus(isKeyWindow: false, isFirstResponder: true)
        #expect(fixture.phase == .hidden)

        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: true)
        #expect(fixture.phase == .on)

        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: false)
        #expect(fixture.phase == .hidden)
    }

    @Test("AC-18: 打つ・動かすと、消えている途中でも点いた状態に戻る")
    func typingAndMovingRestartBlink() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 2))
        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: true)
        fixture.textView.caretView?.send(.tick)
        #expect(fixture.phase == .off)

        fixture.select(1)
        #expect(fixture.phase == .on)

        fixture.textView.caretView?.send(.tick)
        #expect(fixture.phase == .off)
        fixture.textView.insertText("え", replacementRange: NSRange(location: 1, length: 0))
        #expect(fixture.phase == .on)
    }

    @Test("AC-18: システムのカーソルのままのときは、自前のカーソルは点滅しない")
    func systemCaretDoesNotBlinkOwnCaret() {
        let fixture = CaretFixture("あいう", readability: readability(shape: .bar, width: 2))
        fixture.textView.setCaretFocus(isKeyWindow: true, isFirstResponder: true)
        #expect(fixture.phase == .on)

        fixture.textView.applyReadability(readability(shape: .bar, width: 1))
        #expect(fixture.phase == .hidden)
    }

    // MARK: - AC-20

    private func highlighting(_ isOn: Bool = true) -> EditorReadability {
        var value = EditorReadability.standard
        value.highlightsCurrentLine = isOn
        return value
    }

    private func highlightAlpha(of textView: PromptTextView, atX x: CGFloat, y: CGFloat) -> CGFloat? {
        guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / textView.bounds.width
        return bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent
    }

    @Test("AC-20: ハイライトがオンなら、カーソルのある段落の矩形が文章の幅で取れ、別の段落へ動かすと移る")
    func highlightFollowsCaretParagraph() throws {
        let fixture = CaretFixture("あいうえお\nかきくけこ\nさしすせそ", readability: highlighting())
        let origin = fixture.textView.textContainerOrigin
        let containerWidth = try #require(fixture.textView.textContainer).size.width

        fixture.select(1)
        let first = try #require(fixture.textView.currentLineHighlightRect)
        fixture.select(7)
        let second = try #require(fixture.textView.currentLineHighlightRect)
        fixture.select(13)
        let third = try #require(fixture.textView.currentLineHighlightRect)

        #expect(second.minY > first.minY)
        #expect(third.minY > second.minY)
        #expect(second.minY >= first.maxY - 1)
        for rect in [first, second, third] {
            #expect(rect.minX == origin.x)
            #expect(rect.width == containerWidth)
            #expect(rect.width > 0)
            #expect(rect.height > 0)
        }
    }

    @Test("AC-20: 折り返して見えている行の全部を覆う")
    func highlightCoversWrappedLines() throws {
        let long = String(repeating: "あ", count: 80)
        let fixture = CaretFixture(long + "\nいう", readability: highlighting())
        let lineHeight = try #require(fixture.textView.textLayout).baseLineHeight
        fixture.select(2)
        let wrapped = try #require(fixture.textView.currentLineHighlightRect)

        #expect(wrapped.height > lineHeight * 2)
    }

    @Test("AC-20: 折り返した段落の次の段落のハイライトは、その下に付く")
    func highlightBelowWrappedParagraph() throws {
        let long = String(repeating: "あ", count: 80)
        let fixture = CaretFixture(long + "\nいう", readability: highlighting())
        if let layoutManager = fixture.textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        fixture.select(2)
        let wrapped = try #require(fixture.textView.currentLineHighlightRect)
        fixture.select(long.count + 2)
        let next = try #require(fixture.textView.currentLineHighlightRect)

        #expect(next.minY >= wrapped.maxY - 1)
    }

    @Test("AC-20: 文字を選択している間とオフのときは、ハイライトしない")
    func highlightHiddenWhileSelectingOrOff() {
        let fixture = CaretFixture("あいうえお\nかきくけこ", readability: highlighting())
        fixture.select(1)
        #expect(fixture.textView.currentLineHighlightRect != nil)

        fixture.select(1, length: 2)
        #expect(fixture.textView.currentLineHighlightRect == nil)

        fixture.select(1)
        #expect(fixture.textView.currentLineHighlightRect != nil)

        fixture.textView.applyReadability(highlighting(false))
        #expect(fixture.textView.currentLineHighlightRect == nil)

        fixture.textView.applyReadability(highlighting(true))
        #expect(fixture.textView.currentLineHighlightRect != nil)
    }

    @Test("AC-20: 空の入力欄と末尾の改行の後の空の行でも、ハイライトの矩形が取れる")
    func highlightExistsOnEmptyLines() throws {
        let empty = CaretFixture("", readability: highlighting())
        empty.select(0)
        let emptyRect = try #require(empty.textView.currentLineHighlightRect)
        #expect(emptyRect.height > 0)

        let trailing = CaretFixture("a\n", readability: highlighting())
        trailing.select(0)
        let firstLine = try #require(trailing.textView.currentLineHighlightRect)
        trailing.select(2)
        let lastLine = try #require(trailing.textView.currentLineHighlightRect)
        #expect(lastLine.minY > firstLine.minY)
    }

    @Test("AC-20: 文章を打つと、ハイライトが今の段落に付いていく")
    func highlightFollowsTyping() throws {
        let fixture = CaretFixture("あ", readability: highlighting())
        fixture.select(1)
        let before = try #require(fixture.textView.currentLineHighlightRect)

        fixture.textView.insertText("\nい", replacementRange: NSRange(location: 1, length: 0))
        let after = try #require(fixture.textView.currentLineHighlightRect)

        #expect(after.minY > before.minY)
    }

    @Test("AC-20: 色は文章の幅の中の、今の段落の行にだけ塗られる")
    func highlightIsPainted() throws {
        let fixture = CaretFixture("あ\n\n\n\nい", readability: highlighting())
        fixture.select(0)
        let rect = try #require(fixture.textView.currentLineHighlightRect)
        let paintedX = rect.maxX - 8
        let painted = try #require(highlightAlpha(of: fixture.textView, atX: paintedX, y: rect.midY))
        #expect(painted > 0)

        fixture.select(4)
        let moved = try #require(highlightAlpha(of: fixture.textView, atX: paintedX, y: rect.midY))
        #expect(moved == 0)

        fixture.textView.applyReadability(highlighting(false))
        fixture.select(0)
        let off = try #require(highlightAlpha(of: fixture.textView, atX: paintedX, y: rect.midY))
        #expect(off == 0)
    }
}
