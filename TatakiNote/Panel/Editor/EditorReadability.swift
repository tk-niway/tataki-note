import Foundation

/// 入力欄のカーソルの形。
enum EditorCaretShape: String, CaseIterable {
    case bar
    case block
    case underline
}

/// パネルの入力欄の見え方の設定(行間・段落の間隔・字間・1行の長さの上限・字下げ・カーソル・今いる行)。
struct EditorReadability: Equatable {
    /// 行間(倍)。
    var lineHeightMultiple: Double
    /// 段落の間隔(行ぶん)。
    var paragraphSpacingLines: Double
    /// 字間(%)。
    var letterSpacingPercent: Int
    /// 1行の長さの上限(全角の文字数)。`nil` は上限なし。
    var maxLineLength: Int?
    /// 折り返した行の字下げ。
    var indentsWrappedLines: Bool
    /// カーソルの形。
    var caretShape: EditorCaretShape
    /// カーソルの太さ(pt)。
    var caretWidth: Int
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
    static let defaultParagraphSpacingLines = 0.0

    /// 字間の範囲。
    static let letterSpacingPercentRange = 0...20
    /// 字間の初期値。
    static let defaultLetterSpacingPercent = 0

    /// 1行の長さの上限の範囲。
    static let maxLineLengthRange = 20...80
    /// 1行の長さの上限の刻み。
    static let maxLineLengthStep = 5

    /// カーソルの太さの範囲。
    static let caretWidthRange = 1...4
    /// カーソルの太さの初期値。
    static let defaultCaretWidth = 2

    /// 初期値。
    static let standard = EditorReadability(
        lineHeightMultiple: defaultLineHeightMultiple,
        paragraphSpacingLines: defaultParagraphSpacingLines,
        letterSpacingPercent: defaultLetterSpacingPercent,
        maxLineLength: nil,
        indentsWrappedLines: true,
        caretShape: .bar,
        caretWidth: defaultCaretWidth,
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

    /// 1行の長さの上限を範囲に収め、刻みに丸める。`nil` は `nil`。
    static func clampedMaxLineLength(_ value: Int?) -> Int? {
        guard let value else { return nil }
        let clamped = min(max(value, maxLineLengthRange.lowerBound), maxLineLengthRange.upperBound)
        return Int((Double(clamped) / Double(maxLineLengthStep)).rounded()) * maxLineLengthStep
    }

    /// カーソルの太さを範囲に収める。
    static func clampedCaretWidth(_ value: Int) -> Int {
        min(max(value, caretWidthRange.lowerBound), caretWidthRange.upperBound)
    }

    /// 1行の長さの上限を1つ上げる。上限なしより先には進まない。
    static func nextMaxLineLength(after value: Int?) -> Int? {
        guard let current = clampedMaxLineLength(value) else { return nil }
        let next = current + maxLineLengthStep
        return next > maxLineLengthRange.upperBound ? nil : next
    }

    /// 1行の長さの上限を1つ下げる。上限なしの次は最大値。下の端で止まる。
    static func previousMaxLineLength(before value: Int?) -> Int? {
        guard let current = clampedMaxLineLength(value) else { return maxLineLengthRange.upperBound }
        return max(current - maxLineLengthStep, maxLineLengthRange.lowerBound)
    }
}
