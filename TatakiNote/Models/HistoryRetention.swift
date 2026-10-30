import Foundation

/// 履歴を残す期間。
nonisolated enum HistoryRetention: String, CaseIterable {
    case forever
    case thirtyDays
    case sevenDays
    case oneDay

    static let defaultValue: HistoryRetention = .forever

    /// 残す長さ(秒)。無期限なら `nil`。
    var duration: TimeInterval? {
        switch self {
        case .forever:
            nil
        case .thirtyDays:
            30 * 86_400
        case .sevenDays:
            7 * 86_400
        case .oneDay:
            86_400
        }
    }

    /// `now` の時点で、`date` に記録した履歴が期間を過ぎているか。
    func isExpired(_ date: Date, now: Date) -> Bool {
        guard let duration else { return false }
        return now.timeIntervalSince(date) >= duration
    }
}
