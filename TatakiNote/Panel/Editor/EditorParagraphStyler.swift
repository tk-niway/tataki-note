import AppKit

/// 入力欄の文章に、段落ごとの段落スタイル(行間・段落の間隔・字下げ)と字間を付ける。文字は変えない。
struct EditorParagraphStyler {
    let layout: EditorTextLayout
    /// 字下げに使える1行の幅。
    let lineWidth: CGFloat

    /// 文章全体に付け直す。今と同じ属性の段落には触れない。付け直した段落の数を返す。
    @discardableResult
    func apply(to storage: NSTextStorage) -> Int {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return 0 }

        let text = storage.string as NSString
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: whole, options: .byParagraphs) { _, _, enclosingRange, _ in
            paragraphs.append(enclosingRange)
        }

        var prefixWidths: [String: CGFloat] = [:]
        var changes: [(range: NSRange, style: NSParagraphStyle)] = []
        for range in paragraphs {
            let headIndent = headIndent(of: text.substring(with: range) as NSString, cache: &prefixWidths)
            let style = layout.paragraphStyle(headIndent: headIndent)
            if !hasStyle(style, in: range, of: storage) {
                changes.append((range, style))
            }
        }

        let kernNeedsFix = needsKernFix(in: storage, range: whole)
        guard !changes.isEmpty || kernNeedsFix else { return 0 }

        storage.beginEditing()
        for change in changes {
            storage.addAttribute(.paragraphStyle, value: change.style, range: change.range)
        }
        if kernNeedsFix {
            if layout.kern > 0 {
                storage.addAttribute(.kern, value: layout.kern, range: whole)
            } else {
                storage.removeAttribute(.kern, range: whole)
            }
        }
        storage.endEditing()
        return changes.count
    }

    private func headIndent(of paragraph: NSString, cache: inout [String: CGFloat]) -> CGFloat {
        guard layout.readability.indentsWrappedLines else { return 0 }
        let prefixLength = EditorWrapIndent.hangingPrefixLength(of: paragraph)
        guard prefixLength > 0 else { return 0 }
        let prefix = paragraph.substring(to: prefixLength)
        let width: CGFloat
        if let cached = cache[prefix] {
            width = cached
        } else {
            width = prefixWidth(of: prefix)
            cache[prefix] = width
        }
        return EditorWrapIndent.headIndent(prefixWidth: width, lineWidth: lineWidth)
    }

    private func prefixWidth(of prefix: String) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: layout.font]
        if layout.kern > 0 {
            attributes[.kern] = layout.kern
        }
        return NSAttributedString(string: prefix, attributes: attributes).size().width
    }

    private func hasStyle(_ style: NSParagraphStyle, in range: NSRange, of storage: NSTextStorage) -> Bool {
        var effectiveRange = NSRange(location: 0, length: 0)
        let current = storage.attribute(
            .paragraphStyle,
            at: range.location,
            longestEffectiveRange: &effectiveRange,
            in: range
        ) as? NSParagraphStyle
        return current == style && NSEqualRanges(effectiveRange, range)
    }

    private func needsKernFix(in storage: NSTextStorage, range: NSRange) -> Bool {
        let expected = layout.kern
        var needsFix = false
        storage.enumerateAttribute(.kern, in: range, options: []) { value, _, stop in
            let matches: Bool
            if expected > 0 {
                matches = (value as? NSNumber)?.doubleValue == Double(expected)
            } else {
                matches = value == nil
            }
            if !matches {
                needsFix = true
                stop.pointee = true
            }
        }
        return needsFix
    }
}
