import AppKit
import Testing
@testable import TatakiNote

struct EditorBottomPaddingTests {
    // MARK: - 行数と高さ

    @Test("AC-18: 余白の行数は 0〜20 に丸め、初期値は 3")
    func linesAreClamped() {
        #expect(EditorBottomPadding.lineRange == 0...20)
        #expect(EditorBottomPadding.defaultLines == 3)
        #expect(EditorBottomPadding.clampedLines(-5) == 0)
        #expect(EditorBottomPadding.clampedLines(0) == 0)
        #expect(EditorBottomPadding.clampedLines(7) == 7)
        #expect(EditorBottomPadding.clampedLines(20) == 20)
        #expect(EditorBottomPadding.clampedLines(21) == 20)
        #expect(EditorBottomPadding.clampedLines(Int.max) == 20)
        #expect(EditorBottomPadding.clampedLines(Int.min) == 0)
    }

    @Test("AC-19: 余白の高さは「行数 × 1行の高さ」で、範囲外の行数は丸めて数え、0 行なら 0")
    func heightIsLinesTimesLineHeight() {
        #expect(EditorBottomPadding.height(lines: 3, lineHeight: 17) == 51)
        #expect(EditorBottomPadding.height(lines: 0, lineHeight: 17) == 0)
        #expect(EditorBottomPadding.height(lines: 99, lineHeight: 10) == 200)
        #expect(EditorBottomPadding.height(lines: -4, lineHeight: 10) == 0)
    }

    @Test("AC-19: 1行の高さはフォントの既定の行の高さ")
    func lineHeightMatchesFont() {
        let font = NSFont.systemFont(ofSize: 14)
        #expect(EditorBottomPadding.lineHeight(for: font) == NSLayoutManager().defaultLineHeight(for: font))
        #expect(EditorBottomPadding.lineHeight(for: .systemFont(ofSize: 28)) > EditorBottomPadding.lineHeight(for: font))
    }

    @Test("AC-19: 余白を足した inset は、幅はそのままで高さに余白の半分を足し、0 なら元のまま")
    func containerInsetAddsHalfPadding() {
        let base = NSSize(width: 11, height: 4)
        #expect(EditorBottomPadding.containerInset(base: base, padding: 50) == NSSize(width: 11, height: 29))
        #expect(EditorBottomPadding.containerInset(base: base, padding: 0) == base)
    }

    // MARK: - 最後の行

    @Test("AC-20: 範囲が最後の行にあるのは、範囲の後ろに改行が無いとき")
    func lastLineDetection() {
        let text = "ab\ncd" as NSString
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 4, length: 0), of: text))
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 5, length: 0), of: text))
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 3, length: 2), of: text))
        #expect(!EditorBottomPadding.isInLastLine(NSRange(location: 1, length: 0), of: text))
        #expect(!EditorBottomPadding.isInLastLine(NSRange(location: 0, length: 0), of: text))
        #expect(!EditorBottomPadding.isInLastLine(NSRange(location: 0, length: 2), of: text))
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 0, length: 4), of: text))
    }

    @Test("AC-20: 末尾が改行の文章では、改行の後ろが最後の行で、その前は最後の行でない")
    func lastLineAfterTrailingNewline() {
        let text = "ab\n" as NSString
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 3, length: 0), of: text))
        #expect(!EditorBottomPadding.isInLastLine(NSRange(location: 2, length: 0), of: text))
    }

    @Test("AC-20: 空の文章はどの位置でも最後の行で、範囲が文章の外にはみ出しても落ちない")
    func lastLineOfEmptyAndOutOfRange() {
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 0, length: 0), of: "" as NSString))
        #expect(EditorBottomPadding.isInLastLine(NSRange(location: 9, length: 4), of: "ab" as NSString))
    }

    // MARK: - 見せる矩形

    private let caret = CGRect(x: 10, y: 100, width: 0, height: 17)

    @Test("AC-20: 最後の行でないときと、余白が 0 のときは、カーソルの矩形のまま")
    func revealRectKeepsCaretWhenNotNeeded() {
        let notLast = EditorBottomPadding.revealRect(
            caretRect: caret, documentMaxY: 200, visibleHeight: 300, padding: 50, isInLastLine: false
        )
        #expect(notLast == caret)
        let noPadding = EditorBottomPadding.revealRect(
            caretRect: caret, documentMaxY: 200, visibleHeight: 300, padding: 0, isInLastLine: true
        )
        #expect(noPadding == caret)
    }

    @Test("AC-20: 最後の行で、文書の下端までがカーソルから見える高さに収まるなら、下端まで広げる")
    func revealRectExtendsToDocumentBottom() {
        let rect = EditorBottomPadding.revealRect(
            caretRect: caret, documentMaxY: 200, visibleHeight: 300, padding: 50, isInLastLine: true
        )
        #expect(rect.minY == 100)
        #expect(rect.maxY == 200)
        #expect(rect.minX == caret.minX)
    }

    @Test("AC-20: 最後の行で、下端までが見える高さに収まらないなら、カーソルの上端から見える高さまで")
    func revealRectIsLimitedToVisibleHeight() {
        let rect = EditorBottomPadding.revealRect(
            caretRect: caret, documentMaxY: 600, visibleHeight: 300, padding: 50, isInLastLine: true
        )
        #expect(rect.minY == 100)
        #expect(rect.height == 300)
    }
}
