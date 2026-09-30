import AppKit
import Testing
@testable import TatakiNote

/// @note p0-999
@MainActor
struct PanelTextMeasurerTests {
    private let font = NSFont.systemFont(ofSize: 14)
    private let panelWidth: CGFloat = 520

    private func height(_ text: String, font: NSFont? = nil, panelWidth: CGFloat? = nil) -> CGFloat {
        PanelTextMeasurer.textHeight(of: text, font: font ?? self.font, panelWidth: panelWidth ?? self.panelWidth)
    }

    private func lines(_ count: Int) -> String {
        Array(repeating: "a", count: count).joined(separator: "\n")
    }

    @Test("AC-2: 行が増えると高くなり、行の数にほぼ比例する")
    func moreLinesAreTaller() {
        let one = height(lines(1))
        let two = height(lines(2))
        let ten = height(lines(10))

        #expect(one < two)
        #expect(two < ten)
        // @note p0-1000
        let lineHeight = two - one
        #expect(abs((ten - one) - 9 * lineHeight) <= 9)
    }

    @Test("AC-2: 改行の無い長い文章でも、折り返した分だけ高くなる")
    func wrappedTextIsTaller() {
        let wrapped = String(repeating: "あいうえお", count: 40)

        #expect(height(wrapped) > height("あいうえお"))
    }

    @Test("AC-2: 改行で終わる文章は、最後の空の行の分(1行)高い")
    func trailingNewlineAddsOneLine() {
        #expect(height("a\n") > height("a"))
        #expect(abs(height("a\n") - height("a\nb")) <= 1)
    }

    @Test("AC-2: 空の文章でも1行分の高さ(1行の文章と同じ)で、上下の余白を含む")
    func emptyTextIsOneLine() {
        let empty = height("")

        #expect(abs(empty - height("a")) <= 1)
        #expect(empty > 2 * PanelMetrics.textContainerInset.height + 10)
    }

    @Test("AC-5: 文字サイズを上げると高くなる")
    func largerFontIsTaller() {
        let text = lines(5)

        #expect(height(text, font: NSFont.systemFont(ofSize: 20)) > height(text, font: NSFont.systemFont(ofSize: 14)))
    }

    @Test("AC-2: パネルの幅を狭めると、折り返しが増えて高くなる")
    func narrowerPanelIsTaller() {
        let text = String(repeating: "abcde ", count: 40)

        #expect(height(text, panelWidth: 320) > height(text, panelWidth: 520))
    }
}
