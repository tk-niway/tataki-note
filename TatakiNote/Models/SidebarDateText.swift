import Foundation

/// 一覧に出す日時の文字。今年なら「10/18 14:32」、それ以外は「2026/10/18 14:32」。
enum SidebarDateText {
    /// `date` を、`now` と同じ年かどうかで書き分けた文字にする。
    nonisolated static func text(for date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = parts.year ?? 0
        let monthDayTime = String(
            format: "%d/%d %d:%02d",
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0
        )
        guard year != calendar.component(.year, from: now) else { return monthDayTime }
        return "\(year)/\(monthDayTime)"
    }

    /// 西暦・利用者のタイムゾーンの暦。
    nonisolated static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }
}
