import AppKit

/// 入力欄の最後の行の下に空ける余白の計算。
enum EditorBottomPadding {
    /// 余白の行数の範囲。
    static let lineRange = 0...20

    /// 余白の行数の初期値。
    static let defaultLines = 3

    /// 行数を範囲に丸める。
    static func clampedLines(_ lines: Int) -> Int {
        min(max(lines, lineRange.lowerBound), lineRange.upperBound)
    }

    /// フォントの1行の高さ。
    static func lineHeight(for font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    /// 行数ぶんの余白の高さ。
    static func height(lines: Int, lineHeight: CGFloat) -> CGFloat {
        CGFloat(clampedLines(lines)) * lineHeight
    }

    /// 余白を足した textContainerInset。上下に半分ずつ足す。
    static func containerInset(base: NSSize, padding: CGFloat) -> NSSize {
        NSSize(width: base.width, height: base.height + padding / 2)
    }

    /// 範囲が最後の行(後ろに改行が無い)にあるか。
    static func isInLastLine(_ range: NSRange, of text: NSString) -> Bool {
        let end = min(max(NSMaxRange(range), 0), text.length)
        let rest = NSRange(location: end, length: text.length - end)
        return text.rangeOfCharacter(from: .newlines, options: [], range: rest).location == NSNotFound
    }

    /// 自動のスクロールで見せる矩形。最後の行なら余白の下端まで広げる。
    static func revealRect(
        caretRect: CGRect,
        documentMaxY: CGFloat,
        visibleHeight: CGFloat,
        padding: CGFloat,
        isInLastLine: Bool
    ) -> CGRect {
        guard isInLastLine, padding > 0, documentMaxY > caretRect.maxY else { return caretRect }
        let height = min(documentMaxY - caretRect.minY, max(visibleHeight, caretRect.height))
        return CGRect(x: caretRect.minX, y: caretRect.minY, width: caretRect.width, height: height)
    }
}
