import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class ReadabilityUndoDelegate: NSObject, NSTextViewDelegate {
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
private final class ReadabilityFixture {
    static let font = NSFont.systemFont(ofSize: 14)

    let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let delegate = ReadabilityUndoDelegate()
    let pasteboard = PasteboardFixture.makePasteboard()

    init(_ marked: String, readability: EditorReadability, undo: Bool = false) {
        textView.isRichText = false
        textView.pasteboard = pasteboard
        if undo {
            textView.allowsUndo = true
            textView.delegate = delegate
        }
        textView.applyFont(Self.font)
        textView.applyReadability(readability)
        let (text, selection) = MarkedText.parse(marked)
        textView.string = text
        textView.setSelectedRange(selection)
    }

    deinit {
        pasteboard.releaseGlobally()
    }

    var undoManager: UndoManager {
        delegate.textUndoManager
    }

    func writeFullLine(_ line: String) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, LineEditing.fullLinePasteboardType], owner: nil)
        pasteboard.setString(line, forType: .string)
        pasteboard.setString("1", forType: LineEditing.fullLinePasteboardType)
    }

    func paragraphs() -> [(text: String, style: NSParagraphStyle?, kern: CGFloat?)] {
        guard let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        var result: [(text: String, style: NSParagraphStyle?, kern: CGFloat?)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { substring, range, _, _ in
            guard range.length > 0 else { return }
            result.append((
                substring ?? "",
                storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                storage.attribute(.kern, at: range.location, effectiveRange: nil) as? CGFloat
            ))
        }
        return result
    }

    func expectStyled(_ layout: EditorTextLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        let paragraphs = paragraphs()
        #expect(!paragraphs.isEmpty, sourceLocation: sourceLocation)
        for paragraph in paragraphs {
            let label = "段落「\(paragraph.text)」"
            let isBullet = paragraph.text.hasPrefix("- ")
            #expect(paragraph.style?.lineSpacing == layout.lineSpacing, "\(label): 行の間隔", sourceLocation: sourceLocation)
            #expect(
                paragraph.style?.paragraphSpacing == layout.paragraphSpacing,
                "\(label): 段落の間隔",
                sourceLocation: sourceLocation
            )
            #expect(((paragraph.style?.headIndent ?? 0) > 0) == isBullet, "\(label): 字下げ", sourceLocation: sourceLocation)
            #expect(paragraph.kern == layout.kern, "\(label): 字間", sourceLocation: sourceLocation)
        }
    }
}

@MainActor
struct PromptTextViewReadabilityTests {
    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    private let wide = EditorReadability(
        lineHeightMultiple: 1.5,
        paragraphSpacingLines: 1,
        letterSpacingPercent: 10,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    private let plain = EditorReadability(
        lineHeightMultiple: 1.0,
        paragraphSpacingLines: 0,
        letterSpacingPercent: 0,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    private var wideLayout: EditorTextLayout {
        EditorTextLayout(font: ReadabilityFixture.font, readability: wide)
    }

    private var allVariants: [EditorReadability] {
        var variants: [EditorReadability] = []
        var value = EditorReadability.standard
        value.lineHeightMultiple = 2.0
        variants.append(value)
        value = .standard
        value.paragraphSpacingLines = 1.5
        variants.append(value)
        value = .standard
        value.letterSpacingPercent = 20
        variants.append(value)
        value = .standard
        value.indentsWrappedLines = false
        variants.append(value)
        value = .standard
        value.caretShape = .block
        variants.append(value)
        value = .standard
        value.highlightsCurrentLine = true
        variants.append(value)
        variants.append(wide)
        return variants
    }

    private func startComposing(_ marked: String, in textView: PromptTextView) {
        textView.setMarkedText(
            marked,
            selectedRange: NSRange(location: (marked as NSString).length, length: 0),
            replacementRange: noReplacement
        )
    }

    // MARK: - AC-11

    @Test("AC-11: 別の文章に入れ替えると、全体の段落に字下げ・間隔・字間が付き直る")
    func restylesAfterStringReplacement() {
        let fixture = ReadabilityFixture("- 長い箇条書きの項目\nふつうの段落", readability: wide)
        fixture.expectStyled(wideLayout)
        #expect(fixture.paragraphs().map(\.text) == ["- 長い箇条書きの項目", "ふつうの段落"])

        fixture.textView.string = "ふつうの段落\n- 長い箇条書きの項目\n\n- もう1つ"
        fixture.expectStyled(wideLayout)
        #expect(fixture.paragraphs().map(\.text) == ["ふつうの段落", "- 長い箇条書きの項目", "- もう1つ"])
    }

    @Test("AC-11: 打つ・置換すると、その段落の字下げ・字間が付き直る")
    func restylesAfterTypingAndReplacing() {
        let fixture = ReadabilityFixture("ふつうの段落\nあいう", readability: wide)
        let textView = fixture.textView

        textView.insertText("- ", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.string == "- ふつうの段落\nあいう")
        fixture.expectStyled(wideLayout)

        textView.insertText("z", replacementRange: NSRange(location: (textView.string as NSString).length, length: 0))
        #expect(textView.string == "- ふつうの段落\nあいうz")
        fixture.expectStyled(wideLayout)

        textView.insertText("あ", replacementRange: NSRange(location: 0, length: 2))
        #expect(textView.string == "あふつうの段落\nあいうz")
        fixture.expectStyled(wideLayout)
    }

    @Test("AC-11: 行の操作・貼り付け・取り消しの後も、段落の属性が付き直る")
    func restylesAfterLineOperationsPasteAndUndo() {
        let fixture = ReadabilityFixture("- 長い箇条書きの項目|\nふつうの段落", readability: wide, undo: true)
        let textView = fixture.textView

        textView.moveLines(.down)
        #expect(textView.string == "ふつうの段落\n- 長い箇条書きの項目")
        fixture.expectStyled(wideLayout)

        textView.duplicateLines(.down)
        #expect(textView.string == "ふつうの段落\n- 長い箇条書きの項目\n- 長い箇条書きの項目")
        fixture.expectStyled(wideLayout)

        fixture.undoManager.undo()
        #expect(textView.string == "ふつうの段落\n- 長い箇条書きの項目")
        fixture.expectStyled(wideLayout)

        fixture.undoManager.undo()
        #expect(textView.string == "- 長い箇条書きの項目\nふつうの段落")
        fixture.expectStyled(wideLayout)

        fixture.undoManager.redo()
        #expect(textView.string == "ふつうの段落\n- 長い箇条書きの項目")
        fixture.expectStyled(wideLayout)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.writeFullLine("- 貼り付けた行\n")
        textView.pasteLineOrClipboard()
        #expect(textView.string == "- 貼り付けた行\nふつうの段落\n- 長い箇条書きの項目")
        fixture.expectStyled(wideLayout)
        fixture.pasteboard.releaseGlobally()
    }

    @Test("AC-11: 変換中は付け直さず、確定すると付く")
    func restyleWaitsForMarkedTextToBeCommitted() {
        let fixture = ReadabilityFixture("", readability: .standard)
        let textView = fixture.textView
        startComposing("- いろは", in: textView)
        #expect(textView.hasMarkedText())

        textView.applyReadability(wide)
        #expect(textView.pendingRestyle)
        let whileComposing = fixture.paragraphs().first?.style
        #expect(whileComposing?.lineSpacing == 0)
        #expect(whileComposing?.headIndent == 0)

        textView.unmarkText()
        #expect(!textView.hasMarkedText())
        #expect(!textView.pendingRestyle)
        #expect(textView.string == "- いろは")
        fixture.expectStyled(wideLayout)
    }

    @Test("AC-11: 変換中に文字が変わっても付け直しは保留され、変換の確定(insertText)で付く")
    func restyleWaitsUntilInsertTextCommits() {
        let fixture = ReadabilityFixture("", readability: wide)
        let textView = fixture.textView
        startComposing("- いろ", in: textView)
        startComposing("- いろは", in: textView)
        #expect(textView.hasMarkedText())
        #expect(fixture.paragraphs().first?.style?.headIndent == 0)

        textView.insertText("- 色は匂へど", replacementRange: noReplacement)
        #expect(!textView.hasMarkedText())
        #expect(textView.string == "- 色は匂へど")
        fixture.expectStyled(wideLayout)
    }

    @Test("AC-11: 入力欄の幅が変わると、字下げの上限が付き直る")
    func restylesWhenWidthChanges() {
        let fixture = ReadabilityFixture("- 長い箇条書きの項目", readability: wide)
        let textView = fixture.textView
        let wideIndent = fixture.paragraphs().first?.style?.headIndent ?? 0
        #expect(wideIndent > 0)

        textView.setFrameSize(NSSize(width: 20, height: 300))
        let narrowIndent = fixture.paragraphs().first?.style?.headIndent ?? -1
        #expect(narrowIndent >= 0)
        #expect(narrowIndent < wideIndent)

        textView.setFrameSize(NSSize(width: 400, height: 300))
        #expect(fixture.paragraphs().first?.style?.headIndent == wideIndent)
    }

    // MARK: - AC-12

    @Test("AC-12: 6つの設定をどう変えても、入力欄の文字は変わらない")
    func settingsNeverChangeText() {
        let text = "- 長い箇条書きの項目\n\nふつうの段落 with English\n1. 番号付き"
        let fixture = ReadabilityFixture(text, readability: .standard)

        for variant in allVariants + [.standard] {
            fixture.textView.applyReadability(variant)
            #expect(fixture.textView.string == text)
            #expect(fixture.textView.textStorage?.string == text)
        }
    }

    @Test("AC-12: 選択ありのコピーで書かれるのは文字列だけで、設定を変えても中身と種類が同じ")
    func copiedSelectionStaysPlainText() {
        let standard = ReadabilityFixture("- 長い[箇条書き]の項目\nふつう", readability: .standard)
        let styled = ReadabilityFixture("- 長い[箇条書き]の項目\nふつう", readability: wide)
        defer {
            standard.pasteboard.releaseGlobally()
            styled.pasteboard.releaseGlobally()
        }

        standard.textView.writeSelection(to: standard.pasteboard, types: standard.textView.writablePasteboardTypes)
        styled.textView.writeSelection(to: styled.pasteboard, types: styled.textView.writablePasteboardTypes)

        #expect(styled.pasteboard.string(forType: .string) == "箇条書き")
        #expect(standard.pasteboard.string(forType: .string) == "箇条書き")
        #expect(styled.pasteboard.types?.contains(.rtf) == false)
        #expect(styled.pasteboard.types?.contains(.rtfd) == false)
        #expect(Set(styled.pasteboard.types ?? []) == Set(standard.pasteboard.types ?? []))
    }

    @Test("AC-12: 選択なしの行のコピーは、設定を変えても行の文字だけが入る")
    func copiedLineStaysPlainText() {
        let fixture = ReadabilityFixture("ふつう\n- 長い箇条書き|の項目\nおわり", readability: wide)
        defer { fixture.pasteboard.releaseGlobally() }

        fixture.textView.copyLineOrSelection()

        #expect(fixture.pasteboard.string(forType: .string) == "- 長い箇条書きの項目\n")
        #expect(fixture.pasteboard.types?.contains(.rtf) == false)
        #expect(fixture.pasteboard.types?.contains(.rtfd) == false)
    }

    @Test("AC-12: 属性の付け直しは取り消しの履歴に積まれず、文章の編集の取り消しだけが積まれる")
    func restyleIsNotRecordedInUndoHistory() {
        let fixture = ReadabilityFixture("- 長い箇条書きの項目\nふつうの段落", readability: .standard, undo: true)
        fixture.undoManager.removeAllActions()
        #expect(!fixture.undoManager.canUndo)

        for variant in allVariants + [.standard] {
            fixture.textView.applyReadability(variant)
            #expect(!fixture.undoManager.canUndo)
            #expect(!fixture.undoManager.canRedo)
        }

        fixture.textView.setFrameSize(NSSize(width: 250, height: 300))
        fixture.textView.string = "- 別の文章\nふつう"
        fixture.undoManager.removeAllActions()
        fixture.textView.setFrameSize(NSSize(width: 400, height: 300))
        #expect(!fixture.undoManager.canUndo)

        fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.textView.moveLines(.down)
        #expect(fixture.textView.string == "ふつう\n- 別の文章")
        fixture.undoManager.undo()
        #expect(fixture.textView.string == "- 別の文章\nふつう")
        #expect(!fixture.undoManager.canUndo)
    }

    // MARK: - AC-13

    @Test("AC-13: 初期値の設定では、新しく打つ文字に字間 7% と段落の間隔 0.25 行が付く")
    func standardSettingsReachTypingAttributes() {
        let fixture = ReadabilityFixture("", readability: .standard)
        let layout = EditorTextLayout(font: ReadabilityFixture.font, readability: .standard)
        let style = fixture.textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(abs(layout.kern - ReadabilityFixture.font.pointSize * 0.07) < 0.0001)
        #expect((fixture.textView.typingAttributes[.kern] as? CGFloat) == layout.kern)
        #expect(style?.paragraphSpacing == layout.paragraphSpacing)
        #expect((style?.paragraphSpacing ?? 0) > 0)
        #expect(style?.lineSpacing == 0)
    }

    @Test("AC-13: 設定を変えると、新しく打つ文字の属性もその値になり、左右の余白は変わらない")
    func settingsReachTypingAttributesAndInsets() {
        let fixture = ReadabilityFixture("", readability: plain)
        let textView = fixture.textView
        #expect(textView.typingAttributes[.kern] == nil)

        textView.applyReadability(wide)
        let style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.lineSpacing == wideLayout.lineSpacing)
        #expect(style?.paragraphSpacing == wideLayout.paragraphSpacing)
        #expect((textView.typingAttributes[.kern] as? CGFloat) == wideLayout.kern)

        textView.applyReadability(plain)
        #expect(textView.typingAttributes[.kern] == nil)
        #expect((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing == 0)

        textView.baseContainerInset = NSSize(width: 10, height: 8)
        for variant in allVariants {
            textView.applyReadability(variant)
            for width in [200.0, 800.0] {
                textView.setFrameSize(NSSize(width: width, height: 300))
                #expect(textView.textContainerInset.width == 10)
                #expect(textView.textContainerOrigin.x == 10)
            }
        }
    }
}
