import Foundation

/// 履歴に残す件数の上限の範囲。
nonisolated enum HistoryLimit {
    static let defaultValue = 200
    static let range = 10...1000

    /// 範囲の端に丸める。
    static func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
