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

    private func styler(baseKern: CGFloat = 0) -> EditorURLFoldStyler {
        EditorURLFoldStyler(font: font, baseKern: baseKern) { widths($0) }
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

        #expect(kerns.count == fold.schemeRange.length + middle.length)
        for item in kerns where item.location != NSMaxRange(middle) - 1 {
            #expect(item.kern == -7)
        }
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
}
