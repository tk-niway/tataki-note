import Foundation
import Testing
@testable import TatakiNote

struct EditorReadabilityTests {
    @Test("AC-1: 初期値は行間 1.0 倍・段落の間隔 0.25 行・字間 7%・字下げオン・縦線・ハイライトオフ")
    func standardValues() {
        let standard = EditorReadability.standard
        #expect(standard.lineHeightMultiple == 1.0)
        #expect(standard.paragraphSpacingLines == 0.25)
        #expect(standard.letterSpacingPercent == 7)
        #expect(standard.indentsWrappedLines == true)
        #expect(standard.caretShape == .bar)
        #expect(standard.highlightsCurrentLine == false)
    }

    @Test("AC-3: 行間は範囲に収め、0.1 の倍数に丸め、有限でなければ初期値になる")
    func lineHeightMultipleIsClamped() {
        let cases: [(Double, Double)] = [
            (0.5, 1.0), (3.0, 2.0), (1.23, 1.2), (1.26, 1.3), (1.5, 1.5), (2.0, 2.0),
            (.nan, 1.0), (.infinity, 1.0), (-.infinity, 1.0),
        ]
        for (value, expected) in cases {
            #expect(EditorReadability.clampedLineHeightMultiple(value) == expected, "\(value)")
        }
    }

    @Test("AC-3: 段落の間隔は範囲に収め、0.25 の倍数に丸め、有限でなければ初期値になる")
    func paragraphSpacingLinesIsClamped() {
        let cases: [(Double, Double)] = [
            (-1, 0), (5, 2.0), (0.3, 0.25), (0.4, 0.5), (1.75, 1.75), (0, 0),
            (.nan, 0.25), (.infinity, 0.25),
        ]
        for (value, expected) in cases {
            #expect(EditorReadability.clampedParagraphSpacingLines(value) == expected, "\(value)")
        }
    }

    @Test("AC-3: 字間は範囲の端に収める")
    func letterSpacingIsClamped() {
        #expect(EditorReadability.clampedLetterSpacingPercent(-3) == 0)
        #expect(EditorReadability.clampedLetterSpacingPercent(99) == 20)
        #expect(EditorReadability.clampedLetterSpacingPercent(7) == 7)
        #expect(EditorReadability.clampedLetterSpacingPercent(0) == 0)
    }
}
