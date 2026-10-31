/// 挿入先の定期の調べの間隔の決まり。変わらない調べが続くと間隔を伸ばす。
struct InsertionTargetPollSchedule: Equatable {
    static let activeInterval: Duration = .milliseconds(100)
    static let idleInterval: Duration = .milliseconds(250)
    static let unchangedPollsBeforeIdle = 3

    /// 続けて変化の無かった調べの回数(`unchangedPollsBeforeIdle` で頭打ち)。
    private(set) var unchangedPolls = 0

    /// 次の調べまでの間隔。
    var interval: Duration {
        unchangedPolls >= Self.unchangedPollsBeforeIdle ? Self.idleInterval : Self.activeInterval
    }

    /// 1 回の調べで、枠か挿入先が変わったかを記録する。
    mutating func record(changed: Bool) {
        unchangedPolls = changed ? 0 : min(unchangedPolls + 1, Self.unchangedPollsBeforeIdle)
    }

    /// 間隔を短い方に戻す。
    mutating func reset() {
        unchangedPolls = 0
    }
}
