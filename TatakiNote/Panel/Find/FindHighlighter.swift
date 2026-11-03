import AppKit

/// 入力欄に付ける1つのハイライト。
struct FindHighlight: Equatable {
    let range: NSRange
    let isCurrent: Bool
}

/// 一致のハイライトの計算と、入力欄への付け外し。
enum FindHighlighter {
    static let matchColor = NSColor.systemYellow.withAlphaComponent(0.3)
    static let currentColor = NSColor.systemOrange.withAlphaComponent(0.6)

    /// 文章の長さに収まり、長さが 0 でない範囲だけを、今の一致の印を付けて返す。
    static func highlights(_ ranges: [NSRange], current: NSRange?, textLength: Int) -> [FindHighlight] {
        ranges.compactMap { range in
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= textLength
            else { return nil }
            return FindHighlight(range: range, isCurrent: range == current)
        }
    }

    /// 入力欄にハイライトを付け直す(前のものは消す)。
    static func apply(_ highlights: [FindHighlight], to textView: NSTextView) {
        if let layoutManager = textView.textLayoutManager,
           let contentManager = layoutManager.textContentManager {
            applyRendering(highlights, to: layoutManager, contentManager: contentManager)
        } else if let layoutManager = textView.layoutManager {
            applyTemporary(highlights, to: layoutManager, length: (textView.string as NSString).length)
        }
        textView.needsDisplay = true
    }

    private static func applyRendering(
        _ highlights: [FindHighlight],
        to layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager
    ) {
        layoutManager.removeRenderingAttribute(.backgroundColor, for: layoutManager.documentRange)
        for highlight in highlights {
            guard let range = textRange(for: highlight.range, in: contentManager) else { continue }
            layoutManager.addRenderingAttribute(.backgroundColor, value: color(for: highlight), for: range)
        }
    }

    private static func textRange(for range: NSRange, in contentManager: NSTextContentManager) -> NSTextRange? {
        let start = contentManager.documentRange.location
        guard let lower = contentManager.location(start, offsetBy: range.location),
              let upper = contentManager.location(lower, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: lower, end: upper)
    }

    private static func applyTemporary(
        _ highlights: [FindHighlight],
        to layoutManager: NSLayoutManager,
        length: Int
    ) {
        layoutManager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: NSRange(location: 0, length: length)
        )
        for highlight in highlights {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: color(for: highlight),
                forCharacterRange: highlight.range
            )
        }
    }

    private static func color(for highlight: FindHighlight) -> NSColor {
        highlight.isCurrent ? currentColor : matchColor
    }
}
