import Testing
@testable import TatakiNote

struct InsertionTargetPollScheduleTests {
    private typealias Schedule = InsertionTargetPollSchedule

    private func schedule(unchanged: Int) -> Schedule {
        var schedule = Schedule()
        for _ in 0..<unchanged {
            schedule.record(changed: false)
        }
        return schedule
    }

    @Test("AC-1: 記録が無いときは短い間隔")
    func freshScheduleIsActive() {
        #expect(Schedule().interval == Schedule.activeInterval)
    }

    @Test("AC-1: 変化なしが閾値の手前までは短い間隔で、閾値に届くと長い間隔になる")
    func intervalStretchesAtThreshold() {
        for count in 1..<Schedule.unchangedPollsBeforeIdle {
            #expect(schedule(unchanged: count).interval == Schedule.activeInterval)
        }
        #expect(schedule(unchanged: Schedule.unchangedPollsBeforeIdle).interval == Schedule.idleInterval)
    }

    @Test("AC-1: 変化なしがさらに続いても長い間隔のままで、回数は閾値で頭打ちになる")
    func unchangedCountIsCapped() {
        let schedule = schedule(unchanged: Schedule.unchangedPollsBeforeIdle * 4)

        #expect(schedule.interval == Schedule.idleInterval)
        #expect(schedule.unchangedPolls == Schedule.unchangedPollsBeforeIdle)
    }

    @Test("AC-1: 変化ありで短い間隔に戻り、その後の変化なしは閾値の手前までは短いまま")
    func changeReturnsToActive() {
        var schedule = schedule(unchanged: Schedule.unchangedPollsBeforeIdle + 2)

        schedule.record(changed: true)
        #expect(schedule.interval == Schedule.activeInterval)

        for _ in 1..<Schedule.unchangedPollsBeforeIdle {
            schedule.record(changed: false)
        }
        #expect(schedule.interval == Schedule.activeInterval)

        schedule.record(changed: false)
        #expect(schedule.interval == Schedule.idleInterval)
    }

    @Test("AC-1: reset() で短い間隔に戻る")
    func resetReturnsToActive() {
        var schedule = schedule(unchanged: Schedule.unchangedPollsBeforeIdle + 2)

        schedule.reset()

        #expect(schedule.interval == Schedule.activeInterval)
        #expect(schedule.unchangedPolls == 0)
    }
}
