import AppKit
import Testing
@testable import TatakiNote

struct EditorParagraphStylerTests {
    private static let sample = "abc\n  - 長い箇条書きの項目\n1. 番号付き\n・中黒\n"
    private static let lineWidth: CGFloat = 400

    private var font: NSFont {
        NSFont(name: "Menlo-Regular", size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    private let plain = EditorReadability(
        lineHeightMultiple: 1.0,
        paragraphSpacingLines: 0,
        letterSpacingPercent: 0,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    private func readability(_ edit: (inout EditorReadability) -> Void) -> EditorReadability {
        var value = plain
        edit(&value)
        return value
    }

    private func makeStorage(_ text: String = EditorParagraphStylerTests.sample) -> NSTextStorage {
        NSTextStorage(string: text, attributes: [.font: font])
    }

    private func style(at location: Int, in storage: NSTextStorage) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private func start(of paragraph: String, in storage: NSTextStorage) -> Int {
        (storage.string as NSString).range(of: paragraph).location
    }

    private func width(of prefix: String) -> CGFloat {
        NSAttributedString(string: prefix, attributes: [.font: font]).size().width
    }

    private func kernValues(in storage: NSTextStorage) -> [CGFloat?] {
        var values: [CGFloat?] = []
        storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            values.append((value as? NSNumber).map { CGFloat($0.doubleValue) })
        }
        return values
    }

    @Test("AC-4: すべての段落に同じ行の間隔が付く")
    func everyParagraphGetsLineSpacing() {
        let layout = EditorTextLayout(font: font, readability: readability { $0.lineHeightMultiple = 1.5 })
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)

        #expect(layout.lineSpacing > 0)
        for paragraph in ["abc", "  - 長い", "1. 番号", "・中黒"] {
            let applied = style(at: start(of: paragraph, in: storage), in: storage)
            #expect(applied?.lineSpacing == layout.lineSpacing, "\(paragraph)")
        }
    }

    @Test("AC-4: 行間 1.0 倍では行の間隔が 0")
    func standardLineSpacingIsZero() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(style(at: 0, in: storage)?.lineSpacing == 0)
    }

    @Test("AC-5: すべての段落に行間を当てた1行の高さ × n 行の間隔が付き、0 では付かない")
    func everyParagraphGetsParagraphSpacing() {
        let spaced = EditorTextLayout(
            font: font,
            readability: readability {
                $0.lineHeightMultiple = 1.5
                $0.paragraphSpacingLines = 1
            }
        )
        let storage = makeStorage()
        EditorParagraphStyler(layout: spaced, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(spaced.paragraphSpacing > 0)
        for paragraph in ["abc", "1. 番号", "・中黒"] {
            #expect(style(at: start(of: paragraph, in: storage), in: storage)?.paragraphSpacing == spaced.paragraphSpacing, "\(paragraph)")
        }

        let none = EditorTextLayout(font: font, readability: plain)
        EditorParagraphStyler(layout: none, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(style(at: 0, in: storage)?.paragraphSpacing == 0)
    }

    @Test("AC-5: 初期値では、すべての段落に 0.25 行ぶんの間隔が付き、行の間隔は 0")
    func standardParagraphSpacing() {
        let layout = EditorTextLayout(font: font, readability: .standard)
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)

        #expect(abs(layout.paragraphSpacing - 0.25 * layout.lineHeight) < 0.0001)
        for paragraph in ["abc", "1. 番号", "・中黒"] {
            let applied = style(at: start(of: paragraph, in: storage), in: storage)
            #expect(applied?.paragraphSpacing == layout.paragraphSpacing, "\(paragraph)")
            #expect(applied?.lineSpacing == 0, "\(paragraph)")
        }
    }

    @Test("AC-6: 字間が 0 より大きいとき、文章全体に文字サイズ × p / 100 の字間が付く")
    func kernIsAppliedToWholeText() {
        let layout = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 5 })
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)

        let values = kernValues(in: storage)
        #expect(values == [layout.kern])
        #expect(abs(layout.kern - 0.7) < 0.0001)
    }

    @Test("AC-6: 字間 0% の文章には .kern 属性がどこにも無い")
    func noKernAtZeroPercent() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(kernValues(in: storage) == [nil])
    }

    @Test("AC-6: 初期値(字間 7%)では、文章全体に文字サイズ × 7 / 100 の字間が付く")
    func standardKernIsAppliedToWholeText() {
        let layout = EditorTextLayout(font: font, readability: .standard)
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)

        #expect(abs(layout.kern - 0.98) < 0.0001)
        #expect(kernValues(in: storage) == [layout.kern])
    }

    @Test("AC-6: 字間を p% から 0% に戻すと .kern 属性が外れ、別の値にすると付け直される")
    func kernIsRemovedWhenReturningToZero() {
        let storage = makeStorage()
        let five = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 5 })
        EditorParagraphStyler(layout: five, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(kernValues(in: storage) == [five.kern])

        let ten = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 10 })
        EditorParagraphStyler(layout: ten, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(kernValues(in: storage) == [ten.kern])

        let zero = EditorTextLayout(font: font, readability: plain)
        EditorParagraphStyler(layout: zero, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(kernValues(in: storage) == [nil])
    }

    @Test("AC-6: 字間 0 の .kern が付いた文章からも、0% で外れる")
    func zeroKernAttributeIsRemoved() {
        let storage = makeStorage()
        storage.addAttribute(.kern, value: CGFloat(0), range: NSRange(location: 0, length: storage.length))
        let layout = EditorTextLayout(font: font, readability: plain)
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(kernValues(in: storage) == [nil])
    }

    @Test("AC-10: 字下げや箇条書きのある段落の折り返した行は本文の始まりに揃い、1行目はそのまま")
    func wrappedLinesAlignWithBodyStart() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)

        let expected: [(String, CGFloat)] = [
            ("abc", 0),
            ("  - 長い", width(of: "  - ")),
            ("1. 番号", width(of: "1. ")),
            ("・中黒", width(of: "・")),
        ]
        for (paragraph, indent) in expected {
            let applied = style(at: start(of: paragraph, in: storage), in: storage)
            #expect(abs((applied?.headIndent ?? -1) - indent) < 0.001, "\(paragraph)")
            #expect(applied?.firstLineHeadIndent == 0, "\(paragraph)")
        }
    }

    @Test("AC-10: 字下げがオフのときはどの段落も左端のまま")
    func noIndentWhenDisabled() {
        let layout = EditorTextLayout(font: font, readability: readability { $0.indentsWrappedLines = false })
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)
        for paragraph in ["abc", "  - 長い", "1. 番号", "・中黒"] {
            #expect(style(at: start(of: paragraph, in: storage), in: storage)?.headIndent == 0, "\(paragraph)")
        }
    }

    @Test("AC-10: 字下げは1行の幅の半分を超えない")
    func indentIsCappedAtHalfTheLineWidth() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage("        - 項目")
        let narrow = width(of: "        - ") / 2
        EditorParagraphStyler(layout: layout, lineWidth: narrow).apply(to: storage)
        #expect(abs((style(at: 0, in: storage)?.headIndent ?? -1) - narrow / 2) < 0.001)
    }

    @Test("AC-10: 幅が変わると字下げが付け直され、同じ属性の段落には触れない")
    func onlyChangedParagraphsAreRestyled() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage()
        let styler = EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth)

        #expect(styler.apply(to: storage) == 4)
        #expect(styler.apply(to: storage) == 0)

        let narrowWidth = width(of: "  - ") * 1.75
        let narrow = EditorParagraphStyler(layout: layout, lineWidth: narrowWidth)
        #expect(narrow.apply(to: storage) == 1)
        let applied = style(at: start(of: "  - 長い", in: storage), in: storage)
        #expect(abs((applied?.headIndent ?? -1) - narrowWidth / 2) < 0.001)
    }

    @Test("AC-10: 一部の段落だけ編集されたときは、その段落だけが付け直される")
    func editedParagraphIsRestyled() {
        let layout = EditorTextLayout(font: font, readability: plain)
        let storage = makeStorage()
        let styler = EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth)
        styler.apply(to: storage)

        let location = start(of: "1. 番号", in: storage)
        storage.replaceCharacters(in: NSRange(location: location, length: 3), with: "xy ")
        #expect(styler.apply(to: storage) == 1)
        #expect(style(at: location, in: storage)?.headIndent == 0)
    }

    @Test("AC-10: 空の文章には何もしない")
    func emptyTextIsLeftAlone() {
        let layout = EditorTextLayout(font: font, readability: readability { $0.letterSpacingPercent = 5 })
        let storage = makeStorage("")
        #expect(EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage) == 0)
        #expect(storage.length == 0)
    }

    @Test("AC-10: 付け直しても文字は変わらない")
    func textIsNotChanged() {
        let layout = EditorTextLayout(
            font: font,
            readability: readability {
                $0.lineHeightMultiple = 1.6
                $0.paragraphSpacingLines = 0.5
                $0.letterSpacingPercent = 8
            }
        )
        let storage = makeStorage()
        EditorParagraphStyler(layout: layout, lineWidth: Self.lineWidth).apply(to: storage)
        #expect(storage.string == Self.sample)
    }
}
