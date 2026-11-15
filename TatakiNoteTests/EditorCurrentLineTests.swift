import AppKit
import Testing
@testable import TatakiNote

struct EditorCurrentLineTests {
    private func range(_ text: String, _ location: Int, length: Int = 0, isEnabled: Bool = true) -> NSRange? {
        EditorCurrentLine.paragraphRange(
            in: text as NSString,
            selection: NSRange(location: location, length: length),
            isEnabled: isEnabled
        )
    }

    // MARK: - 段落の範囲

    @Test("AC-20: 空の文章では、カーソルの行(長さ 0 の範囲)になる")
    func emptyTextIsCaretLine() {
        #expect(range("", 0) == NSRange(location: 0, length: 0))
    }

    @Test("AC-20: カーソルのある段落の全部(改行を含む)が範囲になる")
    func paragraphAroundCaret() {
        #expect(range("a\nb", 1) == NSRange(location: 0, length: 2))
        #expect(range("a\nb", 2) == NSRange(location: 2, length: 1))
        #expect(range("あいう\nえお\nかき", 5) == NSRange(location: 4, length: 3))
    }

    @Test("AC-20: 末尾の改行の後(空の最後の行)は、長さ 0 の範囲になる")
    func afterTrailingNewline() {
        #expect(range("a\n", 2) == NSRange(location: 2, length: 0))
    }

    @Test("AC-20: 文字を選択している間は、ハイライトしない")
    func noRangeWhileSelecting() {
        #expect(range("abc", 0, length: 1) == nil)
        #expect(range("abc\ndef", 1, length: 4) == nil)
    }

    @Test("AC-20: オフのときは、ハイライトしない")
    func noRangeWhenDisabled() {
        #expect(range("abc", 1, isEnabled: false) == nil)
    }

    @Test("AC-20: 選択の位置が文章の外なら、ハイライトしない")
    func noRangeOutsideText() {
        #expect(range("abc", 9) == nil)
        #expect(range("abc", NSNotFound) == nil)
    }

    // MARK: - 矩形

    @Test("AC-20: 折り返した行の全部を覆い、左右はテキストコンテナの幅になる")
    func rectCoversWrappedLines() {
        let lines = [
            CGRect(x: 20, y: 40, width: 300, height: 17),
            CGRect(x: 30, y: 57, width: 300, height: 17),
            CGRect(x: 30, y: 74, width: 120, height: 17),
        ]
        let rect = EditorCurrentLine.rect(lineRects: lines, caretRect: nil, containerMinX: 10, containerWidth: 380)
        #expect(rect == CGRect(x: 10, y: 40, width: 380, height: 51))
    }

    @Test("AC-20: 中央寄せのときは、文章の幅の左端から文章の幅になる")
    func rectFollowsCenteredContainer() {
        let lines = [CGRect(x: 200, y: 8, width: 100, height: 17)]
        let rect = EditorCurrentLine.rect(lineRects: lines, caretRect: nil, containerMinX: 180, containerWidth: 440)
        #expect(rect?.minX == 180)
        #expect(rect?.width == 440)
    }

    @Test("AC-20: 行の矩形が無いときは、カーソルの行になる")
    func rectFallsBackToCaretLine() {
        let caret = CGRect(x: 15, y: 25, width: 0, height: 17)
        let rect = EditorCurrentLine.rect(lineRects: [], caretRect: caret, containerMinX: 10, containerWidth: 380)
        #expect(rect == CGRect(x: 10, y: 25, width: 380, height: 17))
    }

    @Test("AC-20: 行もカーソルの枠も無い・幅が無いときは、矩形を出さない")
    func rectIsNilWithoutGeometry() {
        #expect(EditorCurrentLine.rect(lineRects: [], caretRect: nil, containerMinX: 10, containerWidth: 380) == nil)
        let lines = [CGRect(x: 0, y: 0, width: 10, height: 17)]
        #expect(EditorCurrentLine.rect(lineRects: lines, caretRect: nil, containerMinX: 10, containerWidth: 0) == nil)
    }
}
