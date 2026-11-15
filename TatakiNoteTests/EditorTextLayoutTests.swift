import AppKit
import Testing
@testable import TatakiNote

struct EditorTextLayoutTests {
    private let plain = EditorReadability(
        lineHeightMultiple: 1.0,
        paragraphSpacingLines: 0,
        letterSpacingPercent: 0,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    private func readability(_ edit: (inout EditorReadability) -> Void) -> EditorReadability {
        var value = plain
        edit(&value)
        return value
    }

    @Test("AC-4: 行間を m 倍にすると行の間隔は (m − 1) × 1行の高さ、1.0 倍では 0")
    func lineSpacingFollowsMultiple() {
        let font = NSFont.systemFont(ofSize: 14)
        let base = EditorBottomPadding.lineHeight(for: font)

        let standard = EditorTextLayout(font: font, readability: .standard)
        #expect(standard.baseLineHeight == base)
        #expect(standard.lineSpacing == 0)
        #expect(standard.lineHeight == base)

        let wide = EditorTextLayout(font: font, readability: readability { $0.lineHeightMultiple = 1.5 })
        #expect(abs(wide.lineSpacing - 0.5 * base) < 0.0001)
        #expect(abs(wide.lineHeight - 1.5 * base) < 0.0001)
        #expect(wide.paragraphStyle(headIndent: 0).lineSpacing == wide.lineSpacing)
    }

    @Test("AC-4: 行間 1.0 倍の段落スタイルは、属性の無いときと同じ高さになる")
    func standardParagraphStyleKeepsHeight() {
        let font = NSFont.systemFont(ofSize: 14)
        let layout = EditorTextLayout(font: font, readability: plain)
        let text = "あいうえお かきくけこ さしすせそ たちつてと\nなにぬねの"
        let unstyled = NSAttributedString(string: text, attributes: [.font: font])
        let styled = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: layout.paragraphStyle(headIndent: 0)]
        )
        let bounds = NSSize(width: 90, height: CGFloat.greatestFiniteMagnitude)
        let unstyledHeight = unstyled.boundingRect(with: bounds, options: .usesLineFragmentOrigin).height
        let styledHeight = styled.boundingRect(with: bounds, options: .usesLineFragmentOrigin).height
        #expect(unstyledHeight == styledHeight)
    }

    @Test("AC-5: 段落の間隔は n × 行間を当てた1行の高さ、0 では付かない")
    func paragraphSpacingFollowsLines() {
        let font = NSFont.systemFont(ofSize: 14)
        let base = EditorBottomPadding.lineHeight(for: font)

        let none = EditorTextLayout(font: font, readability: plain)
        #expect(none.paragraphSpacing == 0)
        #expect(none.paragraphStyle(headIndent: 0).paragraphSpacing == 0)

        let spaced = EditorTextLayout(
            font: font,
            readability: readability {
                $0.lineHeightMultiple = 1.5
                $0.paragraphSpacingLines = 1
            }
        )
        #expect(abs(spaced.paragraphSpacing - 1.5 * base) < 0.0001)
        #expect(spaced.paragraphStyle(headIndent: 0).paragraphSpacing == spaced.paragraphSpacing)

        let quarter = EditorTextLayout(font: font, readability: readability { $0.paragraphSpacingLines = 0.25 })
        #expect(abs(quarter.paragraphSpacing - 0.25 * base) < 0.0001)

        let initial = EditorTextLayout(font: font, readability: .standard)
        #expect(abs(initial.paragraphSpacing - 0.25 * base) < 0.0001)
    }

    @Test("AC-6: 字間は文字サイズ × p / 100 で、文字サイズを変えても割合が保たれる")
    func kernKeepsRatioAcrossFontSizes() {
        let setting = readability { $0.letterSpacingPercent = 5 }
        let small = EditorTextLayout(font: .systemFont(ofSize: 14), readability: setting)
        let large = EditorTextLayout(font: .systemFont(ofSize: 28), readability: setting)
        #expect(abs(small.kern - 0.7) < 0.0001)
        #expect(abs(large.kern - 1.4) < 0.0001)
        #expect(abs(large.kern / large.font.pointSize - small.kern / small.font.pointSize) < 0.0001)
        #expect((small.typingAttributes[.kern] as? CGFloat) == small.kern)

        let initial = EditorTextLayout(font: .systemFont(ofSize: 14), readability: .standard)
        #expect(abs(initial.kern - 0.98) < 0.0001)
        #expect((initial.typingAttributes[.kern] as? CGFloat) == initial.kern)
    }

    @Test("AC-6: 字間 0% の新しく打つ文字には .kern 属性が無い")
    func typingAttributesOmitKernAtZero() {
        let font = NSFont.systemFont(ofSize: 14)
        let zero = EditorTextLayout(font: font, readability: plain)
        #expect(zero.kern == 0)
        #expect(zero.typingAttributes[.kern] == nil)
        #expect((zero.typingAttributes[.font] as? NSFont) == font)

        let spaced = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 5 })
        #expect(spaced.typingAttributes[.kern] != nil)

        let back = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 0 })
        #expect(back.typingAttributes[.kern] == nil)
    }

    @Test("AC-4: 新しく打つ文字の段落スタイルは行間を持ち、字下げが 0")
    func typingAttributesUseZeroHeadIndent() {
        let layout = EditorTextLayout(font: .systemFont(ofSize: 14), readability: readability { $0.lineHeightMultiple = 1.5 })
        let style = layout.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.headIndent == 0)
        #expect(style?.firstLineHeadIndent == 0)
        #expect(style?.lineSpacing == layout.lineSpacing)
    }

    @Test("AC-16: 全角1文字の幅は「あ」を字間つきで測り、測れなければ文字サイズ + 字間にする")
    func fullWidthAdvanceIsMeasuredWithKern() {
        let font = NSFont.systemFont(ofSize: 14)
        var measured: NSAttributedString?
        let spaced = EditorTextLayout(
            font: font,
            readability: readability { $0.letterSpacingPercent = 10 },
            measure: {
                measured = $0
                return 15
            }
        )
        #expect(spaced.fullWidthAdvance == 15)
        #expect(measured?.string == "あ")
        #expect(measured?.attribute(.kern, at: 0, effectiveRange: nil) != nil)

        let unspaced = EditorTextLayout(font: font, readability: plain, measure: {
            measured = $0
            return 14
        })
        #expect(unspaced.fullWidthAdvance == 14)
        #expect(measured?.attribute(.kern, at: 0, effectiveRange: nil) == nil)

        for invalid: CGFloat in [0, -3, .nan, .infinity] {
            let layout = EditorTextLayout(
                font: font,
                readability: readability { $0.letterSpacingPercent = 10 },
                measure: { _ in invalid }
            )
            #expect(abs(layout.fullWidthAdvance - (14 + layout.kern)) < 0.0001, "\(invalid)")
        }
    }
}
