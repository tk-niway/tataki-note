import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

struct EditorWrapIndentTests {
    @Test("AC-9: 行頭の空白・タブ・全角空白の後ろに揃える")
    func alignsAfterLeadingWhitespace() {
        let cases: [(String, Int)] = [
            ("abc", 0), ("", 0), ("  abc", 2), ("\t\tabc", 2), ("\u{3000}abc", 1), (" \t\u{3000}a", 3),
        ]
        for (paragraph, expected) in cases {
            #expect(EditorWrapIndent.hangingPrefixLength(of: paragraph as NSString) == expected, "\(paragraph.debugDescription)")
        }
    }

    @Test("AC-9: 箇条書きの記号とその後ろの空白の後ろに揃える")
    func alignsAfterBulletMarkers() {
        let cases: [(String, Int)] = [
            ("- item", 2), ("  - item", 4), ("* a", 2), ("+ a", 2), ("-  a", 3), ("-\ta", 2),
            ("・項目", 1), ("・ 項目", 2), ("・\u{3000}項目", 2),
            ("1. a", 3), ("12) a", 4), ("123456789. a", 11), ("1.  a", 4), ("  2) a", 5),
        ]
        for (paragraph, expected) in cases {
            #expect(EditorWrapIndent.hangingPrefixLength(of: paragraph as NSString) == expected, "\(paragraph.debugDescription)")
        }
    }

    @Test("AC-9: 記号でないものは揃えない")
    func ignoresNonMarkers() {
        let cases: [(String, Int)] = [
            ("-item", 0), ("-", 0), ("1.5 倍", 0), ("1234567890. a", 0), ("#  見出し", 0), ("1.", 0), ("1)a", 0),
            ("a. b", 0), ("*bold*", 0),
        ]
        for (paragraph, expected) in cases {
            #expect(EditorWrapIndent.hangingPrefixLength(of: paragraph as NSString) == expected, "\(paragraph.debugDescription)")
        }
    }

    @Test("AC-9: 記号は1つだけ読み、改行は数えない")
    func readsOneMarkerAndStopsAtLineBreak() {
        #expect(EditorWrapIndent.hangingPrefixLength(of: "- - a" as NSString) == 2)
        #expect(EditorWrapIndent.hangingPrefixLength(of: "- \n" as NSString) == 2)
        #expect(EditorWrapIndent.hangingPrefixLength(of: "-\n" as NSString) == 0)
        #expect(EditorWrapIndent.hangingPrefixLength(of: "  \n" as NSString) == 2)
        #expect(EditorWrapIndent.hangingPrefixLength(of: "abc\n  d" as NSString) == 0)
    }

    @Test("AC-10: 字下げの幅は接頭辞の幅で、1行の幅の半分を超えない")
    func headIndentIsCappedAtHalfTheLineWidth() {
        #expect(EditorWrapIndent.headIndent(prefixWidth: 30, lineWidth: 400) == 30)
        #expect(EditorWrapIndent.headIndent(prefixWidth: 200, lineWidth: 400) == 200)
        #expect(EditorWrapIndent.headIndent(prefixWidth: 300, lineWidth: 400) == 200)
    }

    @Test("AC-10: 接頭辞が無い・1行の幅が無いときの字下げは 0")
    func headIndentIsZeroWithoutPrefixOrWidth() {
        #expect(EditorWrapIndent.headIndent(prefixWidth: 0, lineWidth: 400) == 0)
        #expect(EditorWrapIndent.headIndent(prefixWidth: 30, lineWidth: 0) == 0)
        #expect(EditorWrapIndent.headIndent(prefixWidth: 30, lineWidth: -5) == 0)
    }
}
