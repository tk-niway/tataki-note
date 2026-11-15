import AppKit

/// フォントと見え方の設定から決まる、入力欄の行の間隔・字間・1行の幅。
struct EditorTextLayout: Equatable {
    /// 幅をちょうど N 文字ぶんにしたときに、浮動小数の誤差で N 文字目が次の行へ回らないための余裕。
    static let lineWidthSlack: CGFloat = 0.5

    /// テキストコンテナの左右の行の余白。
    static let lineFragmentPadding: CGFloat = NSTextContainer().lineFragmentPadding

    let font: NSFont
    let readability: EditorReadability
    /// 行間を当てる前の1行の高さ。
    let baseLineHeight: CGFloat
    /// 全角1文字の送り幅(字間を含む)。
    let fullWidthAdvance: CGFloat

    /// 字間と全角1文字の幅は、`measure` で測る。
    init(
        font: NSFont,
        readability: EditorReadability,
        measure: (NSAttributedString) -> CGFloat = { $0.size().width }
    ) {
        self.font = font
        self.readability = readability
        self.baseLineHeight = EditorBottomPadding.lineHeight(for: font)

        let kern = Self.kern(for: font, readability: readability)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if kern > 0 {
            attributes[.kern] = kern
        }
        let measured = measure(NSAttributedString(string: "あ", attributes: attributes))
        self.fullWidthAdvance = measured.isFinite && measured > 0 ? measured : font.pointSize + kern
    }

    /// 行の下に足す間隔。
    var lineSpacing: CGFloat {
        CGFloat(readability.lineHeightMultiple - 1) * baseLineHeight
    }

    /// 行間を当てた1行の高さ。
    var lineHeight: CGFloat {
        baseLineHeight * CGFloat(readability.lineHeightMultiple)
    }

    /// 段落の後に足す間隔。
    var paragraphSpacing: CGFloat {
        CGFloat(readability.paragraphSpacingLines) * lineHeight
    }

    /// 字間。
    var kern: CGFloat {
        Self.kern(for: font, readability: readability)
    }

    /// 1行の長さの上限から決まる、テキストコンテナの幅の上限。上限なしは nil。
    var maxContainerWidth: CGFloat? {
        guard let maxLineLength = readability.maxLineLength else { return nil }
        return CGFloat(maxLineLength) * fullWidthAdvance + 2 * Self.lineFragmentPadding + Self.lineWidthSlack
    }

    /// 字下げの幅を入れた段落スタイル。1行目はそのまま。
    func paragraphStyle(headIndent: CGFloat) -> NSParagraphStyle {
        let style = (NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = 0
        return style
    }

    /// 新しく打つ文字の属性。字間は 0 より大きいときだけ入る。
    var typingAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle(headIndent: 0),
        ]
        if kern > 0 {
            attributes[.kern] = kern
        }
        return attributes
    }

    /// 空の入力欄のプレースホルダーの左端。文章の始まりの位置。
    func placeholderLeading(viewWidth: CGFloat, baseInset: CGFloat) -> CGFloat {
        EditorLineLength.alignedHorizontalInset(viewWidth: viewWidth, baseInset: baseInset, maxContainerWidth: maxContainerWidth)
            + Self.lineFragmentPadding
    }

    private static func kern(for font: NSFont, readability: EditorReadability) -> CGFloat {
        font.pointSize * CGFloat(readability.letterSpacingPercent) / 100
    }
}
