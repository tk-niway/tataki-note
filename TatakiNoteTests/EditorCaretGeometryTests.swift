import CoreGraphics
import Testing
@testable import TatakiNote

@MainActor
struct EditorCaretGeometryTests {
    private let caret = CGRect(x: 40, y: 20, width: 0, height: 20)
    private let textHeight: CGFloat = 17
    private let fallbackWidth: CGFloat = 7

    private func rect(
        _ shape: EditorCaretShape,
        barWidth: CGFloat = 2,
        caret: CGRect? = nil,
        character: CGRect? = nil
    ) -> CGRect {
        EditorCaretGeometry.rect(
            shape: shape,
            barWidth: barWidth,
            caretRect: caret ?? self.caret,
            textHeight: textHeight,
            characterRect: character,
            fallbackWidth: fallbackWidth
        )
    }

    // MARK: - AC-16

    @Test("AC-16: 縦線は渡した太さの幅で、高さは1行の高さに収まる")
    func barUsesConfiguredWidth() {
        #expect(rect(.bar, barWidth: 4) == CGRect(x: 40, y: 20, width: 4, height: 17))
        #expect(rect(.bar, barWidth: 1) == CGRect(x: 40, y: 20, width: 1, height: 17))
        let short = CGRect(x: 40, y: 20, width: 0, height: 10)
        #expect(rect(.bar, caret: short).height == 10)
    }

    @Test("AC-16: ブロックはカーソルの位置の文字1つぶんの四角になる")
    func blockCoversCharacter() {
        let character = CGRect(x: 40, y: 20.5, width: 14, height: 20)
        #expect(rect(.block, character: character) == CGRect(x: 40, y: 20, width: 14, height: 17))
    }

    @Test("AC-16: 下線は文字1つぶんの幅で、1行の下に付く")
    func underlineSitsAtBottomOfLine() {
        let character = CGRect(x: 40, y: 20, width: 14, height: 20)
        #expect(
            rect(.underline, character: character)
                == CGRect(x: 40, y: 20 + 17 - EditorCaretGeometry.underlineThickness, width: 14, height: 2)
        )
    }

    @Test("AC-16: 行末・空の行・次が改行のときは、ブロックも下線も半角1文字ぶんの幅になる")
    func missingCharacterUsesHalfWidth() {
        #expect(rect(.block, character: nil).width == fallbackWidth)
        #expect(rect(.underline, character: nil).width == fallbackWidth)
    }

    @Test("AC-16: 次の文字が次の行にある折り返しの境目では、半角1文字ぶんの幅になる")
    func characterOnNextLineUsesHalfWidth() {
        let nextLine = CGRect(x: 10, y: 40, width: 14, height: 20)
        #expect(rect(.block, character: nextLine).width == fallbackWidth)
        #expect(rect(.underline, character: nextLine).width == fallbackWidth)
        let sameLine = CGRect(x: 40, y: 20.9, width: 14, height: 20)
        #expect(rect(.block, character: sameLine).width == 14)
    }

    @Test("AC-16: 幅 0 の文字の枠は使わず、半角1文字ぶんにする")
    func emptyCharacterRectUsesHalfWidth() {
        let empty = CGRect(x: 40, y: 20, width: 0, height: 20)
        #expect(rect(.block, character: empty).width == fallbackWidth)
    }

    @Test("AC-16: 枠が返らない空の文書では、入力欄の始まりに1行ぶんの高さの枠を作る")
    func fallbackForEmptyDocument() {
        let result = EditorCaretGeometry.fallbackCaretRect(
            previousLineMaxY: nil,
            containerOrigin: CGPoint(x: 10, y: 8),
            lineFragmentPadding: 5,
            textHeight: 17,
            lineSpacing: 4,
            paragraphSpacing: 6
        )
        #expect(result == CGRect(x: 15, y: 8, width: 0, height: 17))
    }

    @Test("AC-16: 末尾の改行の後は、前の行の下に行間と段落の間隔を足した位置に枠を作る")
    func fallbackAfterTrailingNewline() {
        func fallback(lineSpacing: CGFloat, paragraphSpacing: CGFloat) -> CGRect {
            EditorCaretGeometry.fallbackCaretRect(
                previousLineMaxY: 25,
                containerOrigin: CGPoint(x: 10, y: 8),
                lineFragmentPadding: 5,
                textHeight: 17,
                lineSpacing: lineSpacing,
                paragraphSpacing: paragraphSpacing
            )
        }
        #expect(fallback(lineSpacing: 0, paragraphSpacing: 0) == CGRect(x: 15, y: 25, width: 0, height: 17))
        #expect(fallback(lineSpacing: 4, paragraphSpacing: 6) == CGRect(x: 15, y: 35, width: 0, height: 17))
    }

    @Test("AC-16: 縦線の太さは 2 pt に固定されている")
    func barWidthIsFixedAtTwoPoints() {
        #expect(EditorCaretGeometry.barWidth == 2)
        #expect(rect(.bar, barWidth: EditorCaretGeometry.barWidth).width == 2)
    }

    // MARK: - AC-18

    @Test("AC-18: 自前のカーソルが点滅するのは、窓がキーで入力欄にフォーカスがあり、何も選択していないときだけ")
    func caretIsActiveOnlyWhenFocusedWithoutSelection() {
        #expect(EditorCaretGeometry.isCaretActive(isKeyWindow: true, isFirstResponder: true, selectionLength: 0))
        #expect(!EditorCaretGeometry.isCaretActive(isKeyWindow: false, isFirstResponder: true, selectionLength: 0))
        #expect(!EditorCaretGeometry.isCaretActive(isKeyWindow: true, isFirstResponder: false, selectionLength: 0))
        #expect(!EditorCaretGeometry.isCaretActive(isKeyWindow: true, isFirstResponder: true, selectionLength: 1))
        #expect(!EditorCaretGeometry.isCaretActive(isKeyWindow: true, isFirstResponder: true, selectionLength: 5))
    }
}
