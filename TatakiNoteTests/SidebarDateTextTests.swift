import Foundation
import Testing
@testable import TatakiNote

struct SidebarDateTextTests {
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(
            calendar: calendar(),
            timeZone: tokyo,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    @Test("AC-25: 今年の日時は「月/日 時:分」で、月・日・時は0を詰めず、分は2桁")
    func thisYearOmitsTheYear() {
        let now = Self.date(2026, 10, 18, 20, 0)

        #expect(SidebarDateText.text(for: Self.date(2026, 10, 18, 14, 32), now: now, calendar: Self.calendar()) == "10/18 14:32")
        #expect(SidebarDateText.text(for: Self.date(2026, 1, 5, 9, 5), now: now, calendar: Self.calendar()) == "1/5 9:05")
        #expect(SidebarDateText.text(for: Self.date(2026, 3, 9, 0, 0), now: now, calendar: Self.calendar()) == "3/9 0:00")
    }

    @Test("AC-25: 去年以前・来年以降の日時は先頭に西暦が付く。年の境目も年で判定する")
    func otherYearsShowTheYear() {
        let calendar = Self.calendar()

        #expect(SidebarDateText.text(for: Self.date(2025, 12, 31, 23, 59), now: Self.date(2026, 1, 1, 0, 0), calendar: calendar) == "2025/12/31 23:59")
        #expect(SidebarDateText.text(for: Self.date(2027, 1, 1, 0, 0), now: Self.date(2026, 12, 31, 23, 59), calendar: calendar) == "2027/1/1 0:00")
        #expect(SidebarDateText.text(for: Self.date(2025, 11, 2, 10, 30), now: Self.date(2026, 10, 18, 9, 0), calendar: calendar) == "2025/11/2 10:30")
    }

    @Test("AC-25: 一覧の既定の日時は、暦の設定によらず西暦で出る")
    func defaultDateTextUsesGregorianYears() {
        let past = Date(timeIntervalSince1970: 1_000_000_000)

        #expect(SidebarDateText.gregorian.identifier == .gregorian)
        #expect(SidebarDateText.gregorian.timeZone == TimeZone.current)
        #expect(SidebarModel.defaultDateText(past).hasPrefix("2001/"))
    }
}
