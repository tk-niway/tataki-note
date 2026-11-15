import Foundation
import Testing
@testable import TatakiNote

struct EditorReadabilityTests {
    @Test("AC-1: 初期値は行間 1.0 倍・段落の間隔 0・字間 0%・上限なし・字下げオン・縦線・太さ 2・ハイライトオフ")
    func standardValues() {
        let standard = EditorReadability.standard
        #expect(standard.lineHeightMultiple == 1.0)
        #expect(standard.paragraphSpacingLines == 0)
        #expect(standard.letterSpacingPercent == 0)
        #expect(standard.maxLineLength == nil)
        #expect(standard.indentsWrappedLines == true)
        #expect(standard.caretShape == .bar)
        #expect(standard.caretWidth == 2)
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
            (-1, 0), (5, 2.0), (0.3, 0.25), (0.4, 0.5), (1.75, 1.75),
            (.nan, 0), (.infinity, 0),
        ]
        for (value, expected) in cases {
            #expect(EditorReadability.clampedParagraphSpacingLines(value) == expected, "\(value)")
        }
    }

    @Test("AC-3: 字間・カーソルの太さは範囲の端に収める")
    func integerSettingsAreClamped() {
        #expect(EditorReadability.clampedLetterSpacingPercent(-3) == 0)
        #expect(EditorReadability.clampedLetterSpacingPercent(99) == 20)
        #expect(EditorReadability.clampedLetterSpacingPercent(7) == 7)
        #expect(EditorReadability.clampedCaretWidth(0) == 1)
        #expect(EditorReadability.clampedCaretWidth(9) == 4)
        #expect(EditorReadability.clampedCaretWidth(3) == 3)
    }

    @Test("AC-3: 1行の長さの上限は nil のまま、数は範囲に収めて 5 の倍数に丸める")
    func maxLineLengthIsClamped() {
        #expect(EditorReadability.clampedMaxLineLength(nil) == nil)
        let cases: [(Int, Int)] = [(10, 20), (99, 80), (22, 20), (23, 25), (40, 40), (80, 80), (20, 20)]
        for (value, expected) in cases {
            #expect(EditorReadability.clampedMaxLineLength(value) == expected, "\(value)")
        }
    }

    @Test("AC-3: 1行の長さの上限のステッパーは、20 から 80 まで 5 刻みで進み、上限なしで止まる")
    func nextMaxLineLengthStopsAtNoLimit() {
        #expect(EditorReadability.nextMaxLineLength(after: 20) == 25)
        #expect(EditorReadability.nextMaxLineLength(after: 75) == 80)
        #expect(EditorReadability.nextMaxLineLength(after: 80) == nil)
        #expect(EditorReadability.nextMaxLineLength(after: nil) == nil)
        #expect(EditorReadability.nextMaxLineLength(after: 22) == 25)
    }

    @Test("AC-3: 1行の長さの上限のステッパーは、上限なしから 80 に戻り、20 で止まる")
    func previousMaxLineLengthStopsAtMinimum() {
        #expect(EditorReadability.previousMaxLineLength(before: nil) == 80)
        #expect(EditorReadability.previousMaxLineLength(before: 25) == 20)
        #expect(EditorReadability.previousMaxLineLength(before: 20) == 20)
        #expect(EditorReadability.previousMaxLineLength(before: 23) == 20)
    }

    @Test("AC-3: 上限なしから 5 刻みで下げて上げると、同じ並びを往復する")
    func maxLineLengthStepperRoundTrips() {
        var down: [Int?] = [nil]
        while let last = down.last, EditorReadability.previousMaxLineLength(before: last) != last {
            down.append(EditorReadability.previousMaxLineLength(before: last))
        }
        #expect(down.count == 14)
        #expect(down.first == .some(nil))
        #expect(down.last == .some(20))
        var current: Int? = 20
        var up: [Int?] = [current]
        while let next = Optional(EditorReadability.nextMaxLineLength(after: current)), next != current {
            up.append(next)
            current = next
        }
        #expect(up == Array(down.reversed()))
    }
}
