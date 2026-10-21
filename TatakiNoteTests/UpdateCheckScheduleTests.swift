import Foundation
import Testing
@testable import TatakiNote

struct UpdateCheckScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func shouldCheck(
        enabled: Bool = true,
        online: Bool = true,
        inSession: Bool = false,
        last: Date?,
        at date: Date? = nil
    ) -> Bool {
        UpdateCheckSchedule.shouldCheckInBackground(
            isAutomaticCheckEnabled: enabled,
            isOnline: online,
            isSessionInProgress: inSession,
            lastCheckDate: last,
            now: date ?? now
        )
    }

    @Test("AC-2: 前回の確認が無ければ確かめる")
    func checksWhenNeverChecked() {
        #expect(shouldCheck(last: nil))
    }

    @Test("AC-2: 前回から23時間59分59秒では確かめず、ちょうど24時間で確かめる")
    func checksAtExactlyOneDay() {
        #expect(!shouldCheck(last: now.addingTimeInterval(-(24 * 60 * 60 - 1))))
        #expect(shouldCheck(last: now.addingTimeInterval(-24 * 60 * 60)))
        #expect(shouldCheck(last: now.addingTimeInterval(-24 * 60 * 60 - 1)))
    }

    @Test("AC-2: 前回が今より未来(時計が戻った)なら確かめる")
    func checksWhenClockWentBack() {
        #expect(shouldCheck(last: now.addingTimeInterval(60)))
    }

    @Test("AC-2: 自動の確認がオフ・オフライン・確認中のどれかなら、ほかを満たしていても確かめない")
    func doesNotCheckWhenAnyConditionFails() {
        #expect(!shouldCheck(enabled: false, last: nil))
        #expect(!shouldCheck(online: false, last: nil))
        #expect(!shouldCheck(inSession: true, last: nil))
    }

    @Test("AC-2: 1日ごとの判定の間隔は24時間で、見張りは1時間ごと")
    func intervals() {
        #expect(UpdateCheckSchedule.interval == 86_400)
        #expect(UpdateCheckSchedule.tickInterval == .seconds(3_600))
    }
}
