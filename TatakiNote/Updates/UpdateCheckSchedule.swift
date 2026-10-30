import Foundation

/// 裏で更新を確かめるかの判定。
enum UpdateCheckSchedule {
    static let interval: TimeInterval = 24 * 60 * 60
    static let tickInterval: Duration = .seconds(60 * 60)

    /// 自動の確認がオンで、オンラインで、確認中でなく、前回から1日以上たっているときだけ true。
    static func shouldCheckInBackground(
        isAutomaticCheckEnabled: Bool,
        isOnline: Bool,
        isSessionInProgress: Bool,
        lastCheckDate: Date?,
        now: Date
    ) -> Bool {
        guard isAutomaticCheckEnabled, isOnline, !isSessionInProgress else { return false }
        guard let lastCheckDate else { return true }
        return now < lastCheckDate || now.timeIntervalSince(lastCheckDate) >= interval
    }
}
