import AppKit
import Testing
@testable import TatakiNote

@MainActor
private func backgroundHighlights(of textView: NSTextView) -> [(range: NSRange, color: NSColor)] {
    var result: [(range: NSRange, color: NSColor)] = []
    if let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager {
        layoutManager.enumerateRenderingAttributes(
            from: layoutManager.documentRange.location,
            reverse: false
        ) { _, attributes, range in
            if let color = attributes[.backgroundColor] as? NSColor {
                let start = contentManager.offset(from: contentManager.documentRange.location, to: range.location)
                let length = contentManager.offset(from: range.location, to: range.endLocation)
                result.append((NSRange(location: start, length: length), color))
            }
            return true
        }
    } else if let layoutManager = textView.layoutManager {
        let length = (textView.string as NSString).length
        var index = 0
        while index < length {
            var effective = NSRange(location: 0, length: 0)
            let attributes = layoutManager.temporaryAttributes(atCharacterIndex: index, effectiveRange: &effective)
            if let color = attributes[.backgroundColor] as? NSColor {
                result.append((effective, color))
            }
            index = max(NSMaxRange(effective), index + 1)
        }
    }
    return result
}

@MainActor
struct FindHighlighterTests {
    @Test("AC-24: 文章に収まる長さのある範囲だけを残し、今の一致に印を付ける")
    func keepsOnlyValidRanges() {
        let ranges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 0),
            NSRange(location: 8, length: 3),
            NSRange(location: 9, length: 5),
            NSRange(location: NSNotFound, length: 2),
            NSRange(location: 12, length: 3),
        ]
        let highlights = FindHighlighter.highlights(
            ranges,
            current: NSRange(location: 8, length: 3),
            textLength: 11
        )

        #expect(highlights == [
            FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: false),
            FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true),
        ])
    }

    @Test("AC-24: 今の一致が無ければどれにも強調の印を付けない")
    func noCurrentMeansNoCurrentMark() {
        let highlights = FindHighlighter.highlights(
            [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)],
            current: nil,
            textLength: 10
        )
        #expect(highlights.count == 2)
        #expect(highlights.allSatisfy { !$0.isCurrent })
    }

    @Test("AC-24: 入力欄にはすべての一致に薄い色、今の一致に強い色が付き、付け直すと前のものは消える")
    func appliesAndReplacesBackgroundHighlights() {
        let textView = PromptTextView()
        textView.string = "foo bar foo baz"

        FindHighlighter.apply(
            [
                FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: false),
                FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true),
            ],
            to: textView
        )
        let applied = backgroundHighlights(of: textView)
        #expect(applied.count == 2)
        #expect(applied.first { $0.range == NSRange(location: 0, length: 3) }?.color == FindHighlighter.matchColor)
        #expect(applied.first { $0.range == NSRange(location: 8, length: 3) }?.color == FindHighlighter.currentColor)

        FindHighlighter.apply(
            [FindHighlight(range: NSRange(location: 12, length: 3), isCurrent: false)],
            to: textView
        )
        let replaced = backgroundHighlights(of: textView)
        #expect(replaced.map(\.range) == [NSRange(location: 12, length: 3)])

        FindHighlighter.apply([], to: textView)
        #expect(backgroundHighlights(of: textView).isEmpty)
    }
}
