import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionTargetMonitorPendingTests {
    private typealias Fixture = MonitorFixture

    private func lookupResult(
        element: AXUIElement? = Fixture.fieldA,
        frame: CGRect? = Fixture.frameA,
        lookup: FocusedElementLookup = Fixture.textField,
        duration: TimeInterval = 0.01
    ) -> OpeningTargetLookupResult {
        OpeningTargetLookupResult(
            probe: FocusedElementProbe(element: element, lookup: lookup, frame: frame),
            didQuery: true,
            duration: duration
        )
    }

    private func openPending(_ f: Fixture, app: InsertionTarget = Fixture.editor) -> InsertionTargetLookupToken {
        f.model.present(target: nil, pendingLookupApp: app)
        return f.monitor.beginPending(app: app)
    }

    // MARK: - AC-8 古い答え

    @Test("AC-8: 閉じた直後(見張りの終わりより前)に答えが届いても、挿入先も枠線も変わらない")
    func answerRightAfterDismissIsDiscarded() {
        let f = Fixture()
        let token = openPending(f)

        f.model.dismiss()
        f.monitor.finishPending(token, result: lookupResult())

        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
    }

    @Test("AC-8: 閉じて見張りが終わった後に答えが届いても、挿入先も枠線も変わらない")
    func answerAfterEndIsDiscarded() async {
        let f = Fixture()
        let token = openPending(f)

        f.model.dismiss()
        await f.settle()
        f.monitor.finishPending(token, result: lookupResult())

        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
        #expect(!f.monitor.isAwaitingOpeningLookup)
    }

    @Test("AC-8: 閉じて開き直した後に前の答えが届いても捨て、新しい待ちの答えだけが反映される")
    func answerForPreviousOpeningIsDiscarded() async {
        let f = Fixture()
        let first = openPending(f)
        f.model.dismiss()
        await f.settle()
        let second = openPending(f)

        f.monitor.finishPending(first, result: lookupResult())

        #expect(f.model.target == nil)
        #expect(f.model.isTargetPending)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.monitor.isAwaitingOpeningLookup)

        f.monitor.finishPending(second, result: lookupResult())

        #expect(f.model.target == Fixture.editor)
        #expect(!f.model.isTargetPending)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(!f.monitor.isAwaitingOpeningLookup)
    }

    @Test("AC-8: 同じ番号の答えは2度目を反映しない")
    func secondAnswerWithSameTokenIsIgnored() {
        let f = Fixture()
        let token = openPending(f)

        f.monitor.finishPending(token, result: lookupResult())
        f.monitor.finishPending(token, result: lookupResult(element: nil, frame: nil, lookup: .noFocusedElement))

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
    }

    // MARK: - AC-9 クリックでの選び直し

    @Test("AC-9: 待ちの間に他のアプリの入力欄をクリックすると、その入力欄が挿入先になり、後の答えで上書きされない")
    func clickedFieldIsNotOverwrittenByAnswer() {
        let f = Fixture()
        f.env.windows = [Fixture.window(of: Fixture.browser), Fixture.window(of: Fixture.editor)]
        let token = openPending(f)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()

        #expect(f.model.target == Fixture.browser)
        #expect(!f.model.isTargetPending)
        #expect(f.model.pendingLookupApp == nil)
        #expect(!f.monitor.isAwaitingOpeningLookup)

        f.monitor.finishPending(token, result: lookupResult())

        #expect(f.model.target == Fixture.browser)
        #expect(f.monitor.outline.rect == Fixture.frameB)
    }

    @Test("AC-9: 待ちの間に挿入先のアプリの入力欄でない所をクリックすると、後の答えを使わない")
    func clickOutsideFieldDiscardsAnswer() {
        let f = Fixture()
        let token = openPending(f)
        f.focus(Fixture.fieldA, frame: nil, lookup: Fixture.button, in: Fixture.editor)
        f.env.frontmost = Fixture.editor
        f.env.mouse = f.clickPoint(inside: Fixture.frameA)

        f.monitor.handleClick()

        #expect(f.model.target == nil)
        #expect(!f.model.isTargetPending)
        #expect(f.model.pendingLookupApp == nil)
        #expect(!f.monitor.isAwaitingOpeningLookup)

        f.monitor.finishPending(token, result: lookupResult())

        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
    }

    // MARK: - AC-10 定期の調べ

    @Test("AC-10: 待ちの間は定期の調べで問い合わせず、待ちの印も変えない")
    func refreshDoesNothingWhilePending() {
        let f = Fixture()
        _ = openPending(f)

        f.monitor.refresh()
        f.monitor.refresh()

        #expect(f.probe.targets.isEmpty)
        #expect(f.probe.frameRequests.isEmpty)
        #expect(f.model.isTargetPending)
        #expect(f.model.pendingLookupApp == Fixture.editor)
        #expect(f.monitor.isAwaitingOpeningLookup)
    }

    @Test("AC-10: 遅い答えが届いた後は、休みを置いてから定期の調べに戻る")
    func refreshResumesAfterBackoffAfterSlowAnswer() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        let token = openPending(f)

        f.monitor.finishPending(token, result: lookupResult(duration: InsertionTargetMonitor.slowQueryThreshold + 0.1))
        f.monitor.refresh()

        #expect(f.probe.frameRequests.isEmpty)

        f.env.now = f.env.now.addingTimeInterval(InsertionTargetMonitor.slowQueryBackoff + 0.01)
        f.monitor.refresh()

        #expect(f.probe.frameRequests.count == 1)
        #expect(f.model.target == Fixture.editor)
    }

    @Test("AC-10: 速い答えのときは休みを置かず、すぐ定期の調べに戻る")
    func refreshResumesImmediatelyAfterFastAnswer() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        let token = openPending(f)

        f.monitor.finishPending(token, result: lookupResult(duration: 0.001))
        f.monitor.refresh()

        #expect(f.probe.frameRequests.count == 1)
    }

    @Test("AC-10: 調べ終えた結果で始めた見張りも、遅い調べの後は休みを置く")
    func beginWithSlowLookedUpResultBacksOff() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.model.present(target: nil)

        let start = f.monitor.begin(
            app: Fixture.editor,
            lookedUp: lookupResult(duration: InsertionTargetMonitor.slowQueryThreshold + 0.1)
        )
        f.monitor.refresh()

        #expect(start.target == Fixture.editor)
        #expect(f.probe.targets.isEmpty)
        #expect(f.probe.frameRequests.isEmpty)

        f.env.now = f.env.now.addingTimeInterval(InsertionTargetMonitor.slowQueryBackoff + 0.01)
        f.monitor.refresh()

        #expect(f.probe.frameRequests.count == 1)
    }

    // MARK: - AC-6 見張りの終わり

    @Test("AC-6: 見張りの終わりで待ちが消え、以後の答えを使わない")
    func endCancelsPending() {
        let f = Fixture()
        let token = openPending(f)

        f.monitor.end()
        f.monitor.finishPending(token, result: lookupResult())

        #expect(!f.monitor.isAwaitingOpeningLookup)
        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
    }
}
