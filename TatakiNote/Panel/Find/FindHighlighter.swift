import AppKit

/// 入力欄に付ける1つのハイライト。
struct FindHighlight: Equatable {
    let range: NSRange
    let isCurrent: Bool
}

/// 入力欄の上に重ねて、今の一致の枠線だけを描く view。
final class FindBorderView: NSView {
    /// 枠線を描く一致の範囲。`nil` なら何も描かない。
    var range: NSRange? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let range, let textView = superview as? NSTextView else { return }
        FindHighlighter.drawBorder(around: FindHighlighter.rects(for: range, in: textView))
    }
}

/// 一致のハイライトの計算と、入力欄への付け外し。
enum FindHighlighter {
    /// ほかの一致の薄い塗り。
    static let matchColor = dynamicColor(
        light: NSColor.systemYellow.withAlphaComponent(0.28),
        dark: NSColor.systemYellow.withAlphaComponent(0.22)
    )

    /// 今の一致の濃い塗り。
    static let currentColor = dynamicColor(
        light: NSColor.systemOrange.withAlphaComponent(0.6),
        dark: NSColor.systemOrange.withAlphaComponent(0.55)
    )

    /// 今の一致の枠線。
    static let currentBorderColor = dynamicColor(
        light: NSColor.systemOrange.blended(withFraction: 0.35, of: .black) ?? .systemOrange,
        dark: NSColor.systemOrange.blended(withFraction: 0.25, of: .white) ?? .systemOrange
    )

    /// 今の一致の枠線の太さ。
    static let currentBorderWidth: CGFloat = 1.5

    /// 今の一致に重なる選択の塗りを消した属性にする。
    static func selectedTextAttributes(
        base: [NSAttributedString.Key: Any],
        hidesSelectionFill: Bool
    ) -> [NSAttributedString.Key: Any] {
        guard hidesSelectionFill else { return base }
        var attributes = base
        attributes[.backgroundColor] = NSColor.clear
        return attributes
    }

    /// 今の一致の範囲が選択と同じか。
    static func isCurrentSelected(_ highlights: [FindHighlight], selection: NSRange) -> Bool {
        highlights.contains { $0.isCurrent && $0.range == selection }
    }

    /// 範囲を覆う矩形(入力欄の座標)。
    static func rects(for range: NSRange, in textView: NSTextView) -> [NSRect] {
        let origin = textView.textContainerOrigin
        var rects: [NSRect] = []
        if let layoutManager = textView.textLayoutManager,
           let contentManager = layoutManager.textContentManager,
           let textRange = textRange(for: range, in: contentManager) {
            layoutManager.enumerateTextSegments(in: textRange, type: .highlight, options: []) { _, frame, _, _ in
                rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
                return true
            }
        } else if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                rects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        return rects.filter { !$0.isEmpty }
    }

    /// 矩形に今の一致の枠線を描く。
    static func drawBorder(around rects: [NSRect]) {
        currentBorderColor.setStroke()
        for rect in rects {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: 0), xRadius: 2, yRadius: 2)
            path.lineWidth = currentBorderWidth
            path.stroke()
        }
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

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
