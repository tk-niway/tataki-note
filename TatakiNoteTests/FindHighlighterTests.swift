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
private func alpha(of color: NSColor, in appearance: NSAppearance.Name) -> CGFloat {
    var result: CGFloat = 0
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        result = (color.usingColorSpace(.sRGB) ?? color).alphaComponent
    }
    return result
}

@MainActor
private func rgba(of color: NSColor, in appearance: NSAppearance.Name) -> [CGFloat] {
    var result: [CGFloat] = []
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        let converted = color.usingColorSpace(.sRGB) ?? color
        result = [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
    }
    return result
}

@MainActor
private func brightness(of color: NSColor, in appearance: NSAppearance.Name) -> CGFloat {
    let components = rgba(of: color, in: appearance)
    return components.prefix(3).reduce(0, +)
}

@MainActor
struct FindHighlighterTests {
    @Test("AC-49: ライトでもダークでも、今の一致の塗りはほかの一致より濃く、枠線は不透明")
    func currentMatchIsClearlyStrongerInBothAppearances() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let match = alpha(of: FindHighlighter.matchColor, in: appearance)
            let current = alpha(of: FindHighlighter.currentColor, in: appearance)
            let border = alpha(of: FindHighlighter.currentBorderColor, in: appearance)
            #expect(match > 0)
            #expect(current >= match * 2)
            #expect(border == 1)
        }
    }

    @Test("AC-49: 今の一致の枠線の色は、ライトでは濃く、ダークでは明るい色で、見た目ごとに違う")
    func borderColorDiffersBetweenAppearances() {
        let light = brightness(of: FindHighlighter.currentBorderColor, in: .aqua)
        let dark = brightness(of: FindHighlighter.currentBorderColor, in: .darkAqua)
        #expect(light < dark)
    }

    @Test("AC-49: ほかの一致の塗りと今の一致の塗りは別の色で、ライトとダークで塗りの色が切り替わる")
    func fillColorsDifferByMatchAndAppearance() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let match = rgba(of: FindHighlighter.matchColor, in: appearance)
            let current = rgba(of: FindHighlighter.currentColor, in: appearance)
            #expect(match != current)
        }
        #expect(
            rgba(of: FindHighlighter.currentColor, in: .aqua) != rgba(of: FindHighlighter.currentColor, in: .darkAqua)
        )
    }

    @Test("AC-50: 今の一致が選択と重なるときだけ、選択の塗りを消す")
    func hidesSelectionFillOnlyOverCurrentMatch() {
        let base: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.systemBlue]
        let current = [FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true)]

        #expect(FindHighlighter.isCurrentSelected(current, selection: NSRange(location: 8, length: 3)))
        #expect(!FindHighlighter.isCurrentSelected(current, selection: NSRange(location: 0, length: 3)))
        #expect(!FindHighlighter.isCurrentSelected(
            [FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: false)],
            selection: NSRange(location: 8, length: 3)
        ))

        let hidden = FindHighlighter.selectedTextAttributes(base: base, hidesSelectionFill: true)
        #expect(hidden[.backgroundColor] as? NSColor == NSColor.clear)
        let kept = FindHighlighter.selectedTextAttributes(base: base, hidesSelectionFill: false)
        #expect(kept[.backgroundColor] as? NSColor == NSColor.systemBlue)
    }

    @Test("AC-50: 入力欄は、今の一致を選んでいる間だけ選択の塗りを消し、選択が動くか閉じると戻す")
    func promptTextViewHidesSelectionFillOverCurrentMatch() {
        let textView = PromptTextView()
        textView.string = "foo bar foo baz"
        let original = textView.selectedTextAttributes[.backgroundColor] as? NSColor
        let highlights = [
            FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: false),
            FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true),
        ]

        textView.setSelectedRange(NSRange(location: 8, length: 3))
        textView.storeFindHighlights(highlights)
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == NSColor.clear)

        textView.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == original)

        textView.setSelectedRange(NSRange(location: 8, length: 3))
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == NSColor.clear)

        textView.storeFindHighlights([])
        #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == original)
    }

    @Test("AC-49: 今の一致の枠線は入力欄の上の専用の view に出て、今の一致が無くなると消える。入力欄は TextKit 2 のまま")
    func currentMatchBorderLivesInOverlayView() {
        let textView = PromptTextView()
        textView.string = "foo bar foo baz"
        #expect(textView.textLayoutManager != nil)

        textView.storeFindHighlights([
            FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: false),
            FindHighlight(range: NSRange(location: 8, length: 3), isCurrent: true),
        ])
        let borders = textView.subviews.compactMap { $0 as? FindBorderView }
        #expect(borders.count == 1)
        #expect(borders.first?.range == NSRange(location: 8, length: 3))
        #expect(borders.first?.hitTest(NSPoint(x: 1, y: 1)) == nil)

        textView.storeFindHighlights([FindHighlight(range: NSRange(location: 0, length: 3), isCurrent: true)])
        #expect(textView.subviews.compactMap { $0 as? FindBorderView }.count == 1)
        #expect(borders.first?.range == NSRange(location: 0, length: 3))

        textView.storeFindHighlights([])
        #expect(borders.first?.range == nil)
        #expect(textView.textLayoutManager != nil)
    }

    @Test("AC-49: 窓に載せた入力欄で、今の一致の枠線の矩形は正の大きさで入力欄の内側にあり、改行をまたぐと行ごとに分かれる")
    func borderRectsCoverCurrentMatch() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        textView.string = "foo\nbar baz"
        window.contentView = textView
        defer { window.close() }
        #expect(textView.textLayoutManager != nil)

        let single = FindHighlighter.rects(for: NSRange(location: 4, length: 3), in: textView)
        #expect(single.count == 1)
        for rect in single {
            #expect(rect.width > 0)
            #expect(rect.height > 0)
            #expect(textView.bounds.contains(rect))
        }

        let spanning = FindHighlighter.rects(for: NSRange(location: 2, length: 3), in: textView)
        #expect(spanning.count >= 2)
        for rect in spanning {
            #expect(rect.width > 0)
            #expect(rect.height > 0)
            #expect(textView.bounds.contains(rect))
        }
        let lines = Set(spanning.map(\.minY))
        #expect(lines.count >= 2)

        let later = try #require(single.first)
        let earlier = try #require(FindHighlighter.rects(for: NSRange(location: 0, length: 3), in: textView).first)
        #expect(later.minY > earlier.minY)
    }

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
