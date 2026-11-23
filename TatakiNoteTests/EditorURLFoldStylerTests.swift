import AppKit
import Testing
@testable import TatakiNote

struct EditorURLFoldStylerTests {
    private static let url = "https://example.com/articles/2026/11/very-long-title/final-part"
    private static let text = "前置き \(url) 後書き"

    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private func widths(_ string: String) -> CGFloat {
        string == "…" ? 10 : 7
    }

    private static let iconWidth: CGFloat = 12

    private func styler(baseKern: CGFloat = 0, linkIconWidth: CGFloat? = EditorURLFoldStylerTests.iconWidth) -> EditorURLFoldStyler {
        var styler = EditorURLFoldStyler(font: font, baseKern: baseKern) { widths($0) }
        styler.linkIconWidth = linkIconWidth
        return styler
    }

    private var iconGap: CGFloat {
        EditorURLLinkIcon.gap(pointSize: font.pointSize)
    }

    private func presentations(selection: NSRange = NSRange(location: 0, length: 0)) -> [EditorURLPresentation] {
        EditorURLPresentation.make(
            urls: EditorURLDetector.urls(in: Self.text as NSString),
            selection: selection,
            findRanges: []
        )
    }

    private func makeStorage() -> NSTextStorage {
        NSTextStorage(string: Self.text, attributes: [.font: font])
    }

    @Test("AC-5: 隠す文字の字間は幅の負の値で、間の最後の文字だけ「…」の幅と字間の分を空ける")
    func hiddenKernsCancelWidthAndLeaveRoomForEllipsis() throws {
        let presentations = presentations()
        let fold = try #require(presentations.first?.fold)
        let middle = try #require(fold.middleRange)
        let kerns = styler(baseKern: 1.5).hiddenKerns(for: presentations, in: Self.text as NSString)

        let iconLocation = NSMaxRange(fold.schemeRange) - 1
        #expect(kerns.count == fold.schemeRange.length + middle.length)
        for item in kerns where item.location != NSMaxRange(middle) - 1 && item.location != iconLocation {
            #expect(item.kern == -7)
        }
        let icon = try #require(kerns.first { $0.location == iconLocation })
        #expect(icon.kern == -7 + Self.iconWidth + iconGap)
        let last = try #require(kerns.first { $0.location == NSMaxRange(middle) - 1 })
        #expect(last.kern == -7 + 10 + 1.5)
    }

    @Test("AC-5: 畳まない URL・URL の無い文章からは隠す字間を作らない")
    func noKernsWithoutFold() {
        let revealed = presentations(selection: NSRange(location: 10, length: 0))
        #expect(styler().hiddenKerns(for: revealed, in: Self.text as NSString).isEmpty)
        #expect(styler().hiddenKerns(for: [], in: "" as NSString).isEmpty)
    }

    @Test("AC-5: 字間と印と合字なしを付け、同じ値をもう一度付けても変えない")
    func appliesKernsAndMarks() throws {
        let storage = makeStorage()
        let kerns = styler().hiddenKerns(for: presentations(), in: Self.text as NSString)

        #expect(styler().apply(kerns, to: storage))
        let first = try #require(kerns.first)
        #expect(storage.attribute(.kern, at: first.location, effectiveRange: nil) as? CGFloat == first.kern)
        #expect(storage.attribute(.ligature, at: first.location, effectiveRange: nil) as? Int == 0)
        #expect(storage.attribute(.editorURLHidden, at: first.location, effectiveRange: nil) != nil)
        #expect(storage.attribute(.editorURLHidden, at: 0, effectiveRange: nil) == nil)
        #expect(storage.string == Self.text)

        #expect(!styler().apply(kerns, to: storage))
    }

    @Test("AC-5: 「…」の印は間の最後の文字だけに付き、外すと消える")
    func ellipsisMarkIsOnTheLastMiddleCharacterOnly() throws {
        let storage = makeStorage()
        let presentations = presentations()
        let middle = try #require(presentations.first?.fold?.middleRange)
        let kerns = styler().hiddenKerns(for: presentations, in: Self.text as NSString)
        #expect(kerns.filter(\.isEllipsis).map(\.location) == [NSMaxRange(middle) - 1])

        styler().apply(kerns, to: storage)
        let marked = (0..<storage.length).filter { storage.attribute(.editorURLEllipsis, at: $0, effectiveRange: nil) != nil }
        #expect(marked == [NSMaxRange(middle) - 1])

        styler().apply([], to: storage)
        #expect((0..<storage.length).allSatisfy { storage.attribute(.editorURLEllipsis, at: $0, effectiveRange: nil) == nil })
    }

    @Test("AC-6: 空の字間を渡すと印と字間を外して字間の設定の値に戻す")
    func applyingNothingRestoresBaseKern() {
        for baseKern: CGFloat in [0, 1.5] {
            let storage = makeStorage()
            let kerns = styler(baseKern: baseKern).hiddenKerns(for: presentations(), in: Self.text as NSString)
            styler(baseKern: baseKern).apply(kerns, to: storage)

            #expect(styler(baseKern: baseKern).apply([], to: storage))

            var marked = 0
            storage.enumerateAttribute(.editorURLHidden, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value != nil { marked += range.length }
            }
            #expect(marked == 0)
            let hidden = kerns[0].location
            let kern = storage.attribute(.kern, at: hidden, effectiveRange: nil) as? CGFloat
            #expect(kern == (baseKern > 0 ? baseKern : nil))
            #expect(storage.attribute(.ligature, at: hidden, effectiveRange: nil) == nil)
        }
    }

    // MARK: - AC-30

    private func linkIconLocations(in storage: NSTextStorage) -> [Int] {
        (0..<storage.length).filter { storage.attribute(.editorURLLinkIcon, at: $0, effectiveRange: nil) != nil }
    }

    @Test("AC-30: スキームの最後の文字にだけアイコンの幅とすき間の字間と印が付き、ほかの文字は幅の負の値のまま")
    func linkIconKernIsOnTheLastSchemeCharacterOnly() throws {
        let presentations = presentations()
        let fold = try #require(presentations.first?.fold)
        let iconLocation = NSMaxRange(fold.schemeRange) - 1
        let kerns = styler().hiddenKerns(for: presentations, in: Self.text as NSString)

        #expect(kerns.filter(\.isLinkIcon).map(\.location) == [iconLocation])
        let icon = try #require(kerns.first { $0.location == iconLocation })
        #expect(icon.kern == -7 + Self.iconWidth + iconGap)
        #expect(!icon.isEllipsis)
        let schemeOthers = kerns.filter { $0.location >= fold.schemeRange.location && $0.location < iconLocation }
        #expect(schemeOthers.count == fold.schemeRange.length - 1)
        #expect(schemeOthers.allSatisfy { $0.kern == -7 && !$0.isLinkIcon })
    }

    @Test("AC-30: スキームだけ隠す URL にもアイコンの字間と印が付く")
    func linkIconIsAlsoOnSchemeOnlyFold() throws {
        let text = "前置き https://example.com/abcdefghijk 後書き" as NSString
        let presentations = EditorURLPresentation.make(
            urls: EditorURLDetector.urls(in: text),
            selection: NSRange(location: 0, length: 0),
            findRanges: []
        )
        let fold = try #require(presentations.first?.fold)
        #expect(fold.middleRange == nil)
        let kerns = styler().hiddenKerns(for: presentations, in: text)

        #expect(kerns.count == fold.schemeRange.length)
        #expect(kerns.filter(\.isLinkIcon).map(\.location) == [NSMaxRange(fold.schemeRange) - 1])
        let storage = NSTextStorage(string: text as String, attributes: [.font: font])
        styler().apply(kerns, to: storage)
        #expect(linkIconLocations(in: storage) == [NSMaxRange(fold.schemeRange) - 1])
    }

    @Test("AC-30: アイコンの大きさが取れないときは印を付けず、字間は幅の負の値のまま")
    func noLinkIconWithoutIconWidth() {
        let kerns = styler(linkIconWidth: nil).hiddenKerns(for: presentations(), in: Self.text as NSString)

        #expect(kerns.allSatisfy { !$0.isLinkIcon })
        #expect(kerns.filter { !$0.isEllipsis }.allSatisfy { $0.kern == -7 })
    }

    @Test("AC-30: アイコンの印は付けた位置にだけ付き、字間を外すと印が消えて字間は設定の値に戻る")
    func linkIconMarkIsAppliedAndRemoved() throws {
        for baseKern: CGFloat in [0, 1.5] {
            let storage = makeStorage()
            let presentations = presentations()
            let fold = try #require(presentations.first?.fold)
            let iconLocation = NSMaxRange(fold.schemeRange) - 1
            let kerns = styler(baseKern: baseKern).hiddenKerns(for: presentations, in: Self.text as NSString)

            styler(baseKern: baseKern).apply(kerns, to: storage)
            #expect(linkIconLocations(in: storage) == [iconLocation])
            let kern = storage.attribute(.kern, at: iconLocation, effectiveRange: nil) as? CGFloat
            #expect(kern == -7 + Self.iconWidth + iconGap)
            #expect(!styler(baseKern: baseKern).apply(kerns, to: storage))

            #expect(styler(baseKern: baseKern).apply([], to: storage))
            #expect(linkIconLocations(in: storage).isEmpty)
            let restored = storage.attribute(.kern, at: iconLocation, effectiveRange: nil) as? CGFloat
            #expect(restored == (baseKern > 0 ? baseKern : nil))
        }
    }

    @Test("AC-30: アイコンの位置の字間が変わっても付け直し、印だけが違う場合も付け直す")
    func linkIconChangeIsReapplied() {
        let storage = makeStorage()
        let withIcon = styler().hiddenKerns(for: presentations(), in: Self.text as NSString)
        let withoutIcon = styler(linkIconWidth: nil).hiddenKerns(for: presentations(), in: Self.text as NSString)

        styler().apply(withIcon, to: storage)
        #expect(styler().apply(withoutIcon, to: storage))
        #expect(linkIconLocations(in: storage).isEmpty)
        #expect(styler().apply(withIcon, to: storage))
        #expect(linkIconLocations(in: storage).count == 1)
    }

    // MARK: - AC-5

    private static let secondUrl = "https://example.org/blog/2026/12/another-long-title/last-part"
    private static let twoUrlText = "前置き \(url) 間 \(secondUrl) 後書き"

    private func twoUrlPresentations() -> [EditorURLPresentation] {
        EditorURLPresentation.make(
            urls: EditorURLDetector.urls(in: Self.twoUrlText as NSString),
            selection: NSRange(location: 0, length: 0),
            findRanges: []
        )
    }

    private func attributeSnapshot(of storage: NSTextStorage) -> [String] {
        (0..<storage.length).map { location in
            let attributes = storage.attributes(at: location, effectiveRange: nil)
            let kern = (attributes[.kern] as? NSNumber)?.doubleValue
            let ligature = (attributes[.ligature] as? NSNumber)?.intValue
            return "\(kern.map { "\($0)" } ?? "-")|\(ligature.map { "\($0)" } ?? "-")|"
                + "\(attributes[.editorURLHidden] != nil)|\(attributes[.editorURLEllipsis] != nil)|\(attributes[.editorURLLinkIcon] != nil)"
        }
    }

    @Test("AC-5: 範囲を限った付け直しは、範囲の外の文字の属性を変えず、範囲の中は文書全体の付け直しと同じになる")
    func restrictedApplyTouchesOnlyTheRange() throws {
        let text = Self.twoUrlText as NSString
        let presentations = twoUrlPresentations()
        #expect(presentations.count == 2)
        let kerns = styler(baseKern: 1.5).hiddenKerns(for: presentations, in: text)
        let firstRange = presentations[0].url.range

        let whole = NSTextStorage(string: Self.twoUrlText, attributes: [.font: font])
        styler(baseKern: 1.5).apply(kerns, to: whole)

        let restricted = NSTextStorage(string: Self.twoUrlText, attributes: [.font: font])
        let before = attributeSnapshot(of: restricted)
        #expect(styler(baseKern: 1.5).apply(kerns, to: restricted, in: firstRange))
        let after = attributeSnapshot(of: restricted)
        let wholeSnapshot = attributeSnapshot(of: whole)

        for location in 0..<restricted.length {
            if NSLocationInRange(location, firstRange) {
                #expect(after[location] == wholeSnapshot[location])
            } else {
                #expect(after[location] == before[location])
            }
        }
        #expect(after[firstRange.location..<NSMaxRange(firstRange)].contains { $0.contains("|true|") })
        #expect(!styler(baseKern: 1.5).apply(kerns, to: restricted, in: firstRange))
    }

    @Test("AC-5: 範囲を限って空の字間を渡すと、範囲の中の印だけを外し、範囲の外の印は残る")
    func restrictedApplyRemovesMarksOnlyInTheRange() {
        let text = Self.twoUrlText as NSString
        let presentations = twoUrlPresentations()
        let kerns = styler().hiddenKerns(for: presentations, in: text)
        let storage = NSTextStorage(string: Self.twoUrlText, attributes: [.font: font])
        styler().apply(kerns, to: storage)
        let firstRange = presentations[0].url.range
        let secondRange = presentations[1].url.range

        #expect(styler().apply([], to: storage, in: firstRange))

        func hiddenLocations(in range: NSRange) -> [Int] {
            (range.location..<NSMaxRange(range)).filter { storage.attribute(.editorURLHidden, at: $0, effectiveRange: nil) != nil }
        }
        #expect(hiddenLocations(in: firstRange).isEmpty)
        #expect(!hiddenLocations(in: secondRange).isEmpty)
    }

    @Test("AC-5: 範囲が文章の外にはみ出しても収め、長さ 0 の範囲では何も変えない")
    func restrictedApplyClampsTheRange() {
        let text = Self.twoUrlText as NSString
        let kerns = styler().hiddenKerns(for: twoUrlPresentations(), in: text)
        let storage = NSTextStorage(string: Self.twoUrlText, attributes: [.font: font])

        #expect(!styler().apply(kerns, to: storage, in: NSRange(location: 3, length: 0)))
        #expect(!styler().apply(kerns, to: storage, in: NSRange(location: storage.length + 5, length: 4)))
        #expect(styler().apply(kerns, to: storage, in: NSRange(location: 0, length: storage.length + 100)))
        let whole = NSTextStorage(string: Self.twoUrlText, attributes: [.font: font])
        styler().apply(kerns, to: whole)
        #expect(attributeSnapshot(of: storage) == attributeSnapshot(of: whole))
    }

    // MARK: - AC-10

    @Test("AC-10: 配置の確定の判定は、見え方から決めても、隠す字間の一覧から決めた判定と同じになる")
    func layoutDecisionMatchesHiddenKernDecision() {
        let text = String(repeating: "x", count: 300) as NSString
        let schemeOnly = EditorURLFold(schemeRange: NSRange(location: 50, length: 8), middleRange: nil)
        let middleOnly = EditorURLFold(schemeRange: NSRange(location: 100, length: 0), middleRange: NSRange(location: 104, length: 20))
        let both = EditorURLFold(schemeRange: NSRange(location: 150, length: 8), middleRange: NSRange(location: 158, length: 12))
        func presentation(_ location: Int, _ fold: EditorURLFold?) -> EditorURLPresentation {
            EditorURLPresentation(url: EditorURL(range: NSRange(location: location, length: 40), text: ""), fold: fold)
        }
        let sets: [[EditorURLPresentation]] = [
            [],
            [presentation(50, nil)],
            [presentation(50, schemeOnly)],
            [presentation(100, middleOnly)],
            [presentation(50, schemeOnly), presentation(100, middleOnly), presentation(150, both)],
            [presentation(150, both)],
        ]
        let locations = [0, 49, 50, 51, 100, 103, 104, 105, 150, 151, 200, NSNotFound]
        for presentations in sets {
            let kerns = styler().hiddenKerns(for: presentations, in: text)
            for location in locations {
                let expected = location != NSNotFound && kerns.contains { $0.location < location }
                #expect(EditorURLFoldStyler.needsLayoutBefore(location: location, presentations: presentations) == expected)
                #expect(EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: presentations, markedLocation: location) == expected)
            }
        }
    }

    // MARK: - AC-26

    private func foldedPresentations(_ hiddenRanges: [Range<Int>]) -> [EditorURLPresentation] {
        hiddenRanges.map { hidden in
            let url = EditorURL(range: NSRange(location: hidden.lowerBound, length: hidden.count + 10), text: "")
            let fold = EditorURLFold(
                schemeRange: NSRange(location: hidden.lowerBound, length: hidden.count),
                middleRange: nil
            )
            return EditorURLPresentation(url: url, fold: fold)
        }
    }

    @Test("AC-26: 配置を確定させるのは、変換の位置より前に隠す文字があるときだけ")
    func layoutIsNeededOnlyWhenHiddenTextPrecedesMarkedText() {
        func kerns(_ ranges: [Range<Int>]) -> [EditorURLPresentation] {
            foldedPresentations(ranges)
        }
        let none = EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: [], markedLocation: 10)
        let after = EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: kerns([0..<8, 20..<31]), markedLocation: 40)
        let before = EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: kerns([50..<61]), markedLocation: 40)
        let same = EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: kerns([40..<51]), markedLocation: 40)
        let notFound = EditorURLFoldStyler.needsLayoutBeforeMarkedText(presentations: kerns([0..<8]), markedLocation: NSNotFound)

        #expect(none == false)
        #expect(after == true)
        #expect(before == false)
        #expect(same == false)
        #expect(notFound == false)
    }

    // MARK: - AC-26

    @Test("AC-26: カーソルの位置より前に隠す文字があるときだけ、変換の前の配置の確定が要る")
    func layoutIsNeededOnlyWhenHiddenTextPrecedesCaret() {
        func kerns(_ ranges: [Range<Int>]) -> [EditorURLPresentation] {
            foldedPresentations(ranges)
        }
        let none = EditorURLFoldStyler.needsLayoutBefore(location: 10, presentations: [])
        let after = EditorURLFoldStyler.needsLayoutBefore(location: 40, presentations: kerns([0..<8, 20..<31]))
        let before = EditorURLFoldStyler.needsLayoutBefore(location: 40, presentations: kerns([50..<61]))
        let same = EditorURLFoldStyler.needsLayoutBefore(location: 40, presentations: kerns([40..<51]))
        let notFound = EditorURLFoldStyler.needsLayoutBefore(location: NSNotFound, presentations: kerns([0..<8]))

        #expect(none == false)
        #expect(after == true)
        #expect(before == false)
        #expect(same == false)
        #expect(notFound == false)
    }
}
