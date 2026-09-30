import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PromptTextViewFontTests {
    private let oldFont = NSFont.systemFont(ofSize: 14)
    private let newFont = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
    private let otherFont = NSFont.systemFont(ofSize: 26)

    /// @note p0-1029
    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    /// @note p0-1030
    private func makeTextView(_ text: String, font: NSFont) -> PromptTextView {
        let textView = PromptTextView()
        textView.isRichText = false
        textView.applyFont(font)
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    /// @note p0-1031
    private func fonts(in textView: PromptTextView) -> [NSFont?] {
        guard let storage = textView.textStorage else { return [] }
        var fonts: [NSFont?] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            fonts.append(value as? NSFont)
        }
        return fonts
    }

    private func typingFont(of textView: PromptTextView) -> NSFont? {
        textView.typingAttributes[.font] as? NSFont
    }

    /// @note p0-1032
    private func startComposing(_ marked: String, in textView: PromptTextView) {
        textView.setMarkedText(
            marked,
            selectedRange: NSRange(location: (marked as NSString).length, length: 0),
            replacementRange: noReplacement
        )
    }

    @Test("AC-3: フォントを変えると、書いてある文章全体と、この後に打つ文字のフォントが変わる。文章と選択は変わらない")
    func appliesFontToWholeText() {
        let textView = makeTextView("one\ntwo three", font: oldFont)
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        #expect(fonts(in: textView) == [oldFont])

        textView.applyFont(newFont)
        #expect(textView.font == newFont)
        #expect(fonts(in: textView) == [newFont])
        #expect(typingFont(of: textView) == newFont)
        #expect(textView.string == "one\ntwo three")
        #expect(textView.selectedRange() == NSRange(location: 4, length: 3))

        // @note p0-1033
        textView.applyFont(newFont)
        #expect(fonts(in: textView) == [newFont])
        #expect(typingFont(of: textView) == newFont)
    }

    @Test("AC-3: フォントを変えた後に打つ文字・行の操作で差し込む文字も、新しいフォントになる")
    func insertedTextUsesNewFont() {
        let textView = makeTextView("one", font: oldFont)
        textView.applyFont(newFont)

        textView.insertText("!", replacementRange: noReplacement)
        #expect(textView.string == "one!")
        #expect(fonts(in: textView) == [newFont])

        textView.duplicateLines(.down)
        #expect(textView.string == "one!\none!")
        #expect(fonts(in: textView) == [newFont])

        // @note p0-1034
        let empty = makeTextView("", font: oldFont)
        empty.applyFont(otherFont)
        #expect(typingFont(of: empty) == otherFont)
        empty.insertText("a", replacementRange: noReplacement)
        #expect(fonts(in: empty) == [otherFont])
    }

    @Test("AC-3: 変換中はフォントを変えず、変換が終わる(unmarkText)と、呼び直さなくても取っておいたフォントが当たる")
    func keepsFontWhileComposingAndAppliesOnUnmark() {
        let textView = makeTextView("abc", font: oldFont)
        startComposing("にほんご", in: textView)
        #expect(textView.hasMarkedText())

        textView.applyFont(newFont)
        #expect(fonts(in: textView) == [oldFont])
        #expect(typingFont(of: textView) == oldFont)
        #expect(textView.string == "abcにほんご")

        textView.unmarkText()
        #expect(!textView.hasMarkedText())
        #expect(textView.string == "abcにほんご")
        #expect(fonts(in: textView) == [newFont])
        #expect(typingFont(of: textView) == newFont)

        // @note p0-1035
        textView.applyFont(newFont)
        #expect(fonts(in: textView) == [newFont])
        #expect(typingFont(of: textView) == newFont)
    }

    @Test("AC-3: 変換中に変わったフォントは、変換を確定する(insertText)と、呼び直さなくても当たる")
    func appliesPendingFontOnInsertText() {
        // @note p0-1036
        let converted = makeTextView("abc", font: oldFont)
        startComposing("にほんご", in: converted)
        converted.applyFont(newFont)
        #expect(fonts(in: converted) == [oldFont])

        converted.insertText("日本語", replacementRange: noReplacement)
        #expect(!converted.hasMarkedText())
        #expect(converted.string == "abc日本語")
        #expect(fonts(in: converted) == [newFont])
        #expect(typingFont(of: converted) == newFont)

        // @note p0-1037
        let unchanged = makeTextView("abc", font: oldFont)
        startComposing("にほんご", in: unchanged)
        unchanged.applyFont(newFont)
        unchanged.insertText("にほんご", replacementRange: noReplacement)
        #expect(unchanged.string == "abcにほんご")
        #expect(fonts(in: unchanged) == [newFont])
        #expect(typingFont(of: unchanged) == newFont)
    }

    @Test("AC-3: 変換中に2回変えたら、変換が終わった後は後の方のフォントになる")
    func appliesLatestPendingFont() {
        let textView = makeTextView("abc", font: oldFont)
        startComposing("にほんご", in: textView)

        textView.applyFont(newFont)
        textView.applyFont(otherFont)
        #expect(fonts(in: textView) == [oldFont])

        textView.unmarkText()
        #expect(fonts(in: textView) == [otherFont])
        #expect(typingFont(of: textView) == otherFont)
    }

    @Test("AC-3: 変換中に元のフォントに戻したら、変換が終わっても元のフォントのまま")
    func pendingFontCanBeRevertedWhileComposing() {
        let textView = makeTextView("abc", font: oldFont)
        startComposing("にほんご", in: textView)

        textView.applyFont(newFont)
        textView.applyFont(oldFont)
        textView.unmarkText()
        #expect(fonts(in: textView) == [oldFont])
        #expect(typingFont(of: textView) == oldFont)
    }
}
