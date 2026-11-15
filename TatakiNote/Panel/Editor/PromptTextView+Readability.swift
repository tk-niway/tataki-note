import AppKit

extension PromptTextView {
    // MARK: - 見え方の設定

    /// 見え方の設定を入力欄に当てる。前と同じなら何もしない。
    func applyReadability(_ readability: EditorReadability) {
        guard readability != self.readability || textLayout == nil else { return }
        self.readability = readability
        refreshTextLayout()
    }

    /// 今のフォントと設定から配置を作り直し、違っていれば余白と段落の属性を付け直す。
    func refreshTextLayout() {
        let layout = font.map { EditorTextLayout(font: $0, readability: readability) }
        guard layout != textLayout else { return }
        textLayout = layout
        needsTypingAttributes = true
        updateHorizontalInset()
        restyleText()
    }

    /// 文章の段落ごとの属性を付け直す。変換中は確定の後まで保留する。
    func restyleText() {
        guard !hasMarkedText() else {
            pendingRestyle = true
            return
        }
        pendingRestyle = false
        guard let layout = textLayout, let storage = textStorage else { return }
        if needsTypingAttributes {
            needsTypingAttributes = false
            applyTypingAttributes(of: layout)
        }
        EditorParagraphStyler(layout: layout, lineWidth: lineWidth).apply(to: storage)
    }

    // MARK: - 左右の余白

    /// 1行の長さの上限と入力欄の幅から決まる、左右の余白の幅。
    var resolvedHorizontalInset: CGFloat {
        EditorLineLength.alignedHorizontalInset(
            viewWidth: bounds.width,
            baseInset: baseContainerInset.width,
            maxContainerWidth: textLayout?.maxContainerWidth
        )
    }

    /// 左右の余白が変わるときだけ、余白を当て直す。
    func updateHorizontalInset() {
        let resolved = resolvedHorizontalInset
        guard resolved != horizontalInset else { return }
        horizontalInset = resolved
        applyContainerInset()
    }

    /// 入力欄の幅が変わったときに、余白と段落の属性を決め直す。
    func handleWidthChange() {
        updateHorizontalInset()
        restyleText()
    }

    private var lineWidth: CGFloat {
        max(0, bounds.width - 2 * horizontalInset - 2 * EditorTextLayout.lineFragmentPadding)
    }

    private func applyTypingAttributes(of layout: EditorTextLayout) {
        let style = layout.paragraphStyle(headIndent: 0)
        typingAttributes[.paragraphStyle] = style
        if layout.kern > 0 {
            typingAttributes[.kern] = layout.kern
        } else {
            typingAttributes[.kern] = nil
        }
        defaultParagraphStyle = style
    }
}
