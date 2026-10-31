import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionTargetMonitorPollIntervalTests {
    private typealias Fixture = MonitorFixture
    private typealias Schedule = InsertionTargetPollSchedule

    private func lookupResult() -> OpeningTargetLookupResult {
        OpeningTargetLookupResult(
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.textField, frame: Fixture.frameA),
            didQuery: true,
            duration: 0.01
        )
    }

    private func openedFixture(polls: Bool = false) -> Fixture {
        let f = Fixture(polls: polls)
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        return f
    }

    private func stretch(_ f: Fixture) {
        for _ in 0..<Schedule.unchangedPollsBeforeIdle {
            f.monitor.refresh()
        }
        #expect(f.monitor.nextPollInterval == Schedule.idleInterval)
    }

    private func waitForSleeps(_ f: Fixture, count: Int) async {
        for _ in 0..<500 where f.env.sleeps.count < count {
            await Task.yield()
        }
    }

    // MARK: - AC-2 間隔が短い方に戻る出来事

    @Test("AC-2: 開いた直後と開き直した直後は、次の調べまでの間隔が短い")
    func intervalIsActiveRightAfterOpening() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)

        f.open(Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)

        stretch(f)
        f.open(Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-2: 見張りを終えると、次の調べまでの間隔が短くなる")
    func intervalIsActiveAfterEnd() {
        let f = openedFixture()
        stretch(f)

        f.monitor.end()

        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-2: 開くときの答えが届いた直後は、次の調べまでの間隔が短い")
    func intervalIsActiveRightAfterOpeningAnswer() {
        let f = Fixture()
        f.model.present(target: nil, pendingLookupApp: Fixture.editor)
        let token = f.monitor.beginPending(app: Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
        stretch(f)

        f.monitor.finishPending(token, result: lookupResult())

        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
        #expect(f.model.target == Fixture.editor)
    }

    @Test("AC-2: クリックで入力欄を選び直した直後は、次の調べまでの間隔が短い")
    func intervalIsActiveRightAfterClickAdoption() {
        let f = openedFixture()
        stretch(f)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.windows = [Fixture.window(of: Fixture.browser), Fixture.window(of: Fixture.editor)]
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()

        #expect(f.model.target == Fixture.browser)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    // MARK: - AC-3 定期の調べの待ち

    @Test("AC-3: 定期の調べは次の調べまでの間隔だけ待ち、入力欄が動かない間は短い間隔から長い間隔に伸び、パネルを閉じると止まる")
    func pollingWaitsForNextInterval() async {
        let f = openedFixture(polls: true)
        await waitForSleeps(f, count: Schedule.unchangedPollsBeforeIdle + 3)

        let sleeps = f.env.sleeps
        #expect(sleeps.count >= Schedule.unchangedPollsBeforeIdle + 3)
        #expect(sleeps.prefix(Schedule.unchangedPollsBeforeIdle).allSatisfy { $0 == Schedule.activeInterval })
        #expect(sleeps.dropFirst(Schedule.unchangedPollsBeforeIdle).allSatisfy { $0 == Schedule.idleInterval })

        f.model.dismiss()
        await f.settle()
        let sleepsAfterDismiss = f.env.sleeps.count
        let requestsAfterDismiss = f.probe.frameRequests.count
        await f.settle()

        #expect(f.env.sleeps.count == sleepsAfterDismiss)
        #expect(f.probe.frameRequests.count == requestsAfterDismiss)
    }

    // MARK: - AC-4 間隔が伸びた後の追従

    @Test("AC-4: 間隔が伸びた後でも、入力欄が動くと次の1回の調べで枠が動き、その後の間隔は短い")
    func outlineFollowsFieldAfterStretch() {
        let f = openedFixture()
        stretch(f)

        f.probe.elementFrames[7001] = Fixture.frameB
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.monitor.outline.rect == Fixture.frameB)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-4: 間隔が伸びた後でも、入力欄が他のウィンドウに隠れるとその調べで枠が消え、表に出るとその調べで出る")
    func outlineHidesAndReappearsAfterStretch() {
        let f = openedFixture()
        stretch(f)

        f.env.windows = [Fixture.window(of: Fixture.browser), Fixture.window(of: Fixture.editor)]
        let hidden = f.monitor.refresh()

        #expect(hidden)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)

        stretch(f)
        f.env.windows = [Fixture.window(of: Fixture.editor)]
        let shown = f.monitor.refresh()

        #expect(shown)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    // MARK: - AC-5 間隔が伸びた後の挿入先なし

    @Test("AC-5: 間隔が伸びた後でも、入力欄の位置が読めなくなると次の1回の調べで挿入先なしになる")
    func unreadableFieldClearsTargetAfterStretch() {
        let f = openedFixture()
        stretch(f)

        f.probe.elementFrames[7001] = nil
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-5: 間隔が伸びた後でも、挿入先のアプリが終了すると次の1回の調べで挿入先なしになる")
    func terminatedAppClearsTargetAfterStretch() {
        let f = openedFixture()
        stretch(f)

        f.env.stoppedProcesses.insert(Fixture.editor.processIdentifier)
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-5: 開いている間にフォーカスが別の入力欄へ移っても、挿入先は変わらず、間隔も短くならない")
    func focusMoveKeepsTargetAndInterval() {
        let f = openedFixture()
        stretch(f)
        let probesBefore = f.probe.targets.count

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        let changed = f.monitor.refresh()

        #expect(!changed)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.monitor.nextPollInterval == Schedule.idleInterval)
        #expect(f.probe.targets.count == probesBefore)
    }

    // MARK: - AC-6 時間の歯止めと答え待ち

    @Test("AC-6: 遅いアプリの休みの間は問い合わせずに変化なしと数え、休みが明けた調べでは問い合わせる")
    func slowAppBackoffCountsAsUnchanged() {
        let f = Fixture()
        f.probe.onFrameRequest = { f.env.now += 0.05 }
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.monitor.refresh()
        #expect(f.probe.frameRequests.count == 1)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)

        for _ in 1..<Schedule.unchangedPollsBeforeIdle {
            f.probe.elementFrames[7001] = Fixture.frameB
            f.monitor.refresh()
        }

        #expect(f.probe.frameRequests.count == 1)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.monitor.nextPollInterval == Schedule.idleInterval)

        f.env.now += InsertionTargetMonitor.slowQueryBackoff + 0.1
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.probe.frameRequests.count == 2)
        #expect(f.monitor.outline.rect == Fixture.frameB)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-6: 開くときの答えを待つ間は問い合わせずに変化なしと数える")
    func awaitingOpeningAnswerCountsAsUnchanged() {
        let f = Fixture()
        f.model.present(target: nil, pendingLookupApp: Fixture.editor)
        let token = f.monitor.beginPending(app: Fixture.editor)

        stretch(f)

        #expect(f.probe.frameRequests.isEmpty)
        #expect(f.model.target == nil)

        f.monitor.finishPending(token, result: lookupResult())
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    // MARK: - AC-7 枠線のオンとオフ

    @Test("AC-7: 枠線がオフのときも同じ間隔の決まりで、ウィンドウの一覧は取らず、入力欄が使えなくなると挿入先なしになる")
    func outlineDisabledUsesSameScheduleWithoutWindowList() {
        let f = Fixture()
        f.env.isOutlineEnabled = false
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)

        stretch(f)
        #expect(f.env.windowListCalls == 0)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.model.target == Fixture.editor)

        f.probe.elementFrames[7001] = nil
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.model.target == nil)
        #expect(f.env.windowListCalls == 0)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }

    @Test("AC-7: 枠線をオンからオフに切り替えると、その調べで枠が消えて間隔が短くなる")
    func switchingOutlineOffClearsOutlineAndResetsInterval() {
        let f = openedFixture()
        stretch(f)
        #expect(f.monitor.outline.rect == Fixture.frameA)

        f.env.isOutlineEnabled = false
        let changed = f.monitor.refresh()

        #expect(changed)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.nextPollInterval == Schedule.activeInterval)
    }
}
