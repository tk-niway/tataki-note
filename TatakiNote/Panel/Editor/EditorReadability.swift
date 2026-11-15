import Foundation

/// 入力欄のカーソルの形。
enum EditorCaretShape: String, CaseIterable {
    case bar
    case block
    case underline
}

/// パネルの入力欄の見え方の設定(行間・段落の間隔・字間・字下げ・カーソルの形・今いる行)。
struct EditorReadability: Equatable {
    /// 行間(倍)。
    var lineHeightMultiple: Double
    /// 段落の間隔(行ぶん)。
    var paragraphSpacingLines: Double
    /// 字間(%)。
    var letterSpacingPercent: Int
    /// 折り返した行の字下げ。
    var indentsWrappedLines: Bool
    /// カーソルの形。
    var caretShape: EditorCaretShape
    /// 今いる行のハイライト。
    var highlightsCurrentLine: Bool

    /// 行間の範囲。
    static let lineHeightMultipleRange: ClosedRange<Double> = 1.0...2.0
    /// 行間の刻み。
    static let lineHeightMultipleStep = 0.1
    /// 行間の初期値。
    static let defaultLineHeightMultiple = 1.0

    /// 段落の間隔の範囲。
    static let paragraphSpacingLinesRange: ClosedRange<Double> = 0...2.0
    /// 段落の間隔の刻み。
    static let paragraphSpacingLinesStep = 0.25
    /// 段落の間隔の初期値。
    static let defaultParagraphSpacingLines = 0.25

    /// 字間の範囲。
    static let letterSpacingPercentRange = 0...20
    /// 字間の初期値。
    static let defaultLetterSpacingPercent = 7

    /// 初期値。
    static let standard = EditorReadability(
        lineHeightMultiple: defaultLineHeightMultiple,
        paragraphSpacingLines: defaultParagraphSpacingLines,
        letterSpacingPercent: defaultLetterSpacingPercent,
        indentsWrappedLines: true,
        caretShape: .bar,
        highlightsCurrentLine: false
    )

    /// 行間を範囲に収め、刻みに丸める。有限でなければ初期値。
    static func clampedLineHeightMultiple(_ value: Double) -> Double {
        guard value.isFinite else { return defaultLineHeightMultiple }
        let clamped = min(max(value, lineHeightMultipleRange.lowerBound), lineHeightMultipleRange.upperBound)
        return (clamped * 10).rounded() / 10
    }

    /// 段落の間隔を範囲に収め、刻みに丸める。有限でなければ初期値。
    static func clampedParagraphSpacingLines(_ value: Double) -> Double {
        guard value.isFinite else { return defaultParagraphSpacingLines }
        let clamped = min(max(value, paragraphSpacingLinesRange.lowerBound), paragraphSpacingLinesRange.upperBound)
        return (clamped * 4).rounded() / 4
    }

    /// 字間を範囲に収める。
    static func clampedLetterSpacingPercent(_ value: Int) -> Int {
        min(max(value, letterSpacingPercentRange.lowerBound), letterSpacingPercentRange.upperBound)
    }
}
