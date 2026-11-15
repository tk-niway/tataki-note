import AppKit
import Testing
@testable import TatakiNote

struct EditorTextLayoutTests {
    private func readability(_ edit: (inout EditorReadability) -> Void) -> EditorReadability {
        var value = EditorReadability.standard
        edit(&value)
        return value
    }

    private func lineCount(of layout: EditorTextLayout, characters: Int) -> Int? {
        guard let width = layout.maxContainerWidth else { return nil }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1000))
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: String(repeating: "あ", count: characters), attributes: layout.typingAttributes)
        )
        guard let manager = textView.textLayoutManager else { return nil }
        manager.ensureLayout(for: manager.documentRange)
        var count = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            count += fragment.textLineFragments.count
            return true
        }
        return count
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
        let layout = EditorTextLayout(font: font, readability: .standard)
        let text = "あいうえお かきくけこ さしすせそ たちつてと\nなにぬねの"
        let plain = NSAttributedString(string: text, attributes: [.font: font])
        let styled = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: layout.paragraphStyle(headIndent: 0)]
        )
        let bounds = NSSize(width: 90, height: CGFloat.greatestFiniteMagnitude)
        let plainHeight = plain.boundingRect(with: bounds, options: .usesLineFragmentOrigin).height
        let styledHeight = styled.boundingRect(with: bounds, options: .usesLineFragmentOrigin).height
        #expect(plainHeight == styledHeight)
    }

    @Test("AC-5: 段落の間隔は n × 行間を当てた1行の高さ、0 では付かない")
    func paragraphSpacingFollowsLines() {
        let font = NSFont.systemFont(ofSize: 14)
        let base = EditorBottomPadding.lineHeight(for: font)

        let none = EditorTextLayout(font: font, readability: .standard)
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
    }

    @Test("AC-6: 字間 0% の新しく打つ文字には .kern 属性が無い")
    func typingAttributesOmitKernAtZero() {
        let font = NSFont.systemFont(ofSize: 14)
        let zero = EditorTextLayout(font: font, readability: .standard)
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

    @Test("AC-7: 文章の幅の上限は N × 全角1文字の送り幅 + 左右の行の余白 + 0.5pt、上限なしは nil")
    func maxContainerWidthFollowsLineLength() {
        let font = NSFont.systemFont(ofSize: 14)
        let padding = NSTextContainer().lineFragmentPadding

        let unlimited = EditorTextLayout(font: font, readability: .standard, measure: { _ in 20 })
        #expect(unlimited.maxContainerWidth == nil)

        let limited = EditorTextLayout(font: font, readability: readability { $0.maxLineLength = 20 }, measure: { _ in 20 })
        #expect(limited.fullWidthAdvance == 20)
        #expect(limited.maxContainerWidth == 20 * 20 + 2 * padding + 0.5)
        #expect(EditorTextLayout.lineWidthSlack == 0.5)
    }

    @Test("AC-7: 全角1文字の幅は「あ」を字間つきで測り、測れなければ文字サイズ + 字間にする")
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

        let plain = EditorTextLayout(font: font, readability: .standard, measure: {
            measured = $0
            return 14
        })
        #expect(plain.fullWidthAdvance == 14)
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

    @Test("AC-7: プレースホルダーの左端は、上限なしなら今と同じ、上限より広ければ中央寄せの余白 + 行の余白")
    func placeholderLeadingFollowsInset() {
        let font = NSFont.systemFont(ofSize: 14)
        let padding = NSTextContainer().lineFragmentPadding

        let unlimited = EditorTextLayout(font: font, readability: .standard)
        #expect(unlimited.placeholderLeading(viewWidth: 2000, baseInset: 10) == 10 + padding)

        let limited = EditorTextLayout(font: font, readability: readability { $0.maxLineLength = 20 }, measure: { _ in 10 })
        let width = limited.maxContainerWidth ?? 0
        #expect(limited.placeholderLeading(viewWidth: width + 100, baseInset: 10) == 50 + padding)
        #expect(limited.placeholderLeading(viewWidth: width, baseInset: 10) == 10 + padding)
    }

    @Test("AC-15: 上限なしのプレースホルダーの左端は、どの幅でも今の「基本の余白 + 行の余白」と同じ")
    func placeholderLeadingWithoutLimitMatchesCurrentInset() {
        let layout = EditorTextLayout(font: .systemFont(ofSize: 14), readability: .standard)
        let current = PanelMetrics.textContainerInset.width + NSTextContainer().lineFragmentPadding
        for width in [0, 300, 520, 2000] as [CGFloat] {
            #expect(layout.placeholderLeading(viewWidth: width, baseInset: PanelMetrics.textContainerInset.width) == current)
        }
    }

    @Test("AC-15: 中央寄せのプレースホルダーの左端は、中央寄せの余白 + 行の余白")
    func placeholderLeadingCenteredAddsLinePadding() {
        let layout = EditorTextLayout(
            font: .systemFont(ofSize: 14),
            readability: readability { $0.maxLineLength = 20 }
        )
        let base = PanelMetrics.textContainerInset.width
        let maxWidth = layout.maxContainerWidth ?? 0
        let inset = EditorLineLength.alignedHorizontalInset(viewWidth: 800, baseInset: base, maxContainerWidth: maxWidth)
        #expect(inset > base)
        #expect(inset == inset.rounded())
        #expect(layout.placeholderLeading(viewWidth: 800, baseInset: base) == inset + NSTextContainer().lineFragmentPadding)
    }

    @Test("AC-8: 文字サイズ・字間を変えても、上限 N 文字の幅に全角の文字がちょうど N 文字まで1行に入る")
    func exactlyLimitCharactersFitOnOneLine() {
        for size in [14.0, 24.0] {
            for percent in [0, 20] {
                for limit in [20, 40] {
                    let layout = EditorTextLayout(
                        font: .systemFont(ofSize: size),
                        readability: readability {
                            $0.letterSpacingPercent = percent
                            $0.maxLineLength = limit
                        }
                    )
                    let label = "size=\(size) kern=\(percent)% limit=\(limit)"
                    #expect(lineCount(of: layout, characters: limit) == 1, "\(label): N 文字")
                    #expect(lineCount(of: layout, characters: limit + 1) == 2, "\(label): N+1 文字")
                }
            }
        }
    }
}
