import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelCommitFlowFocusMovedTests {
    private static let ownPid: pid_t = 4242

    private let other = InsertionTarget(processIdentifier: 7001, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let fieldE = AXUIElementCreateApplication(pid_t.max)
    private let fieldF = AXUIElementCreateApplication(pid_t.max - 1)
    private let fieldG = AXUIElementCreateApplication(pid_t.max - 2)

    @MainActor
    private final class Fixture {
        enum Event: Equatable {
            case hide
            case reopen
            case insertionRequested(String, InsertionTarget, Bool)
        }

        let model = PanelModel()
        let library = DraftLibrary(store: .inMemory)
        let session: DraftSession
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .focusMoved)
        let probe = FocusedElementProbeStub()
        let monitor: InsertionTargetMonitor
        let sizing = PanelSizing()
        let flow: PanelCommitFlow
        private(set) var events: [Event] = []
        private(set) var noticeMessages: [String] = []

        init(target: InsertionTarget, field: AXUIElement) {
            session = DraftSession(panel: model, library: library, ownProcessIdentifier: PanelCommitFlowFocusMovedTests.ownPid)
            probe.result = FocusedElementProbe(
                element: field,
                lookup: WatcherFixture.textFieldLookup,
                frame: CGRect(x: 0, y: 0, width: 100, height: 20)
            )
            probe.elementFrame = CGRect(x: 0, y: 0, width: 100, height: 20)
            monitor = InsertionTargetMonitor.testFactory(
                probe: probe,
                ownProcessIdentifier: PanelCommitFlowFocusMovedTests.ownPid,
                frontmostApplication: { target }
            )(model)
            flow = PanelCommitFlow(
                model: model,
                session: session,
                library: library,
                permission: permission,
                inserter: inserter,
                targetMonitor: monitor,
                sizing: sizing,
                ownProcessIdentifier: PanelCommitFlowFocusMovedTests.ownPid
            )
            flow.onHide = { [weak self] in self?.events.append(.hide) }
            flow.onReopen = { [weak self] in
                self?.events.append(.reopen)
                self?.model.present(target: target)
            }
            flow.onNotice = { [weak self] message in self?.noticeMessages.append(message) }
            flow.onInsertionRequested = { [weak self] text, target, shouldSend in
                self?.events.append(.insertionRequested(text, target, shouldSend))
            }
            let start = monitor.begin(app: target)
            model.present(target: start.target)
        }

        func finish() {
            monitor.end()
        }

        func focus(_ element: AXUIElement, frame: CGRect? = nil) {
            probe.result = FocusedElementProbe(element: element, lookup: WatcherFixture.textFieldLookup, frame: frame)
        }
    }

    private func waitFor(_ condition: () -> Bool) async {
        _ = try? await waitUntil(attempts: 300, interval: .milliseconds(10), condition)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    private func expectReopenedWithNotice(shouldSend: Bool) async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .focusMoved
        fixture.model.text = "committed"
        fixture.sizing.userDidResize(from: CGSize(width: 520, height: 340), to: CGSize(width: 640, height: 400))
        let heldSize = fixture.sizing.heldSize
        let alertsBefore = fixture.model.noTargetAlertCount

        fixture.flow.commit(shouldSendAfterInsert: shouldSend)
        await waitFor { !fixture.noticeMessages.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, shouldSend), .reopen])
        #expect(fixture.model.isPresented)
        #expect(fixture.model.text == "committed")
        #expect(fixture.model.target == nil)
        #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.sizing.heldSize == heldSize)
        #expect(fixture.noticeMessages == [PanelCommitFlow.focusMovedMessage])
    }

    // MARK: - AC-7

    @Test("AC-7: フォーカスが移っていたときの知らせの文は、確定+挿入でも確定+送信でも「入力欄を選択し直してください」で、確かめられなかったときの文は変わらない")
    func noticeTable() {
        let cases: [(CommitOutcome, Bool, String?)] = [
            (.focusMoved, false, "入力欄を選択し直してください"),
            (.focusMoved, true, "入力欄を選択し直してください"),
            (.notConfirmed, false, PanelCommitFlow.notConfirmedInsertedMessage),
            (.notConfirmed, true, PanelCommitFlow.notConfirmedSentMessage),
            (.inserted, false, nil),
            (.insertedIntoSecureField, true, nil),
            (.notInserted, false, nil),
            (.notInserted, true, nil),
        ]
        for (outcome, shouldSend, expected) in cases {
            #expect(PanelCommitFlow.notice(for: outcome, shouldSendAfterInsert: shouldSend) == expected)
        }
        #expect(PanelCommitFlow.focusMovedMessage == "入力欄を選択し直してください")
        #expect(PanelCommitFlow.notConfirmedSentMessage == "送信できませんでした")
        #expect(PanelCommitFlow.notConfirmedInsertedMessage == "挿入できませんでした")
    }

    @Test("AC-7: フォーカスが移っていたときのパネルの戻し方は、確かめられなかったときと同じ")
    func recoveryTable() {
        typealias Recovery = PanelCommitFlow.FailureRecovery
        let cases: [(Bool, Bool, Recovery)] = [
            (false, true, .reopen),
            (true, true, .rejectTarget),
            (false, false, .none),
            (true, false, .none),
        ]
        for (isPresented, isTextRestored, expected) in cases {
            #expect(PanelCommitFlow.recovery(for: .focusMoved, isPresented: isPresented, isTextRestored: isTextRestored) == expected)
            #expect(
                PanelCommitFlow.recovery(for: .focusMoved, isPresented: isPresented, isTextRestored: isTextRestored)
                    == PanelCommitFlow.recovery(for: .notConfirmed, isPresented: isPresented, isTextRestored: isTextRestored)
            )
        }
    }

    @Test("AC-7: 閉じている間にパネルを開き直していて本文が確定した文章のままなら、開き直さずに挿入先を外して合図を1回増やし、知らせる", arguments: [false, true])
    func focusMovedOverReopenedPanelRejectsTarget(shouldSend: Bool) async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .focusMoved
        fixture.inserter.onInsert = { [model = fixture.model, other] in model.present(target: other) }
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: shouldSend)
        await waitFor { !fixture.noticeMessages.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, shouldSend)])
        #expect(fixture.model.isPresented)
        #expect(fixture.model.text == "committed")
        #expect(fixture.model.target == nil)
        #expect(fixture.model.noTargetAlertCount == 1)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.noticeMessages == [PanelCommitFlow.focusMovedMessage])
    }

    @Test("AC-7: 閉じている間に新しい文章を書き始めていれば、何もせず、知らせない")
    func focusMovedOverNewTextDoesNothing() async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .focusMoved
        fixture.inserter.onInsert = { [model = fixture.model] in model.text = "new" }
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { !fixture.inserter.calls.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, false)])
        #expect(fixture.model.text == "new")
        #expect(fixture.model.noTargetAlertCount == 0)
        #expect(fixture.noticeMessages.isEmpty)
    }

    // MARK: - AC-8

    @Test("AC-8: 確定すると、パネルを隠す前に見張っていた入力欄が挿入に渡される")
    func passesTrackedFieldReadBeforeHiding() async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .inserted
        fixture.flow.onHide = { [monitor = fixture.monitor] in monitor.end() }
        fixture.model.text = "hello"

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { !fixture.inserter.calls.isEmpty }

        #expect(fixture.inserter.expectedFields.count == 1)
        #expect(fixture.inserter.expectedFields.first.flatMap { $0 }.map { CFEqual($0, fieldE) } == true)
        #expect(fixture.monitor.trackedField == nil)
    }

    @Test("AC-8: 開いている間にフォーカスが別の要素へ移り、定期の調べを挟んでも、渡す入力欄は開いたときの入力欄のまま")
    func trackedFieldStaysWhenFocusMoves() async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .inserted
        fixture.model.text = "hello"

        fixture.focus(fieldF, frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        fixture.monitor.refresh()
        fixture.monitor.refresh()
        fixture.flow.commit(shouldSendAfterInsert: true)
        await waitFor { !fixture.inserter.calls.isEmpty }

        #expect(fixture.inserter.expectedFields.count == 1)
        #expect(fixture.inserter.expectedFields.first.flatMap { $0 }.map { CFEqual($0, fieldE) } == true)
    }

    @Test("AC-8: クリックで入力欄を選び直すと、渡す入力欄は選び直した入力欄になる")
    func trackedFieldFollowsClickReselection() async {
        let fixture = Fixture(target: other, field: fieldE)
        defer { fixture.finish() }
        fixture.inserter.result = .inserted
        fixture.model.text = "hello"

        fixture.focus(fieldG, frame: nil)
        fixture.monitor.handleClick()
        #expect(fixture.monitor.trackedField.map { CFEqual($0, fieldG) } == true)
        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { !fixture.inserter.calls.isEmpty }

        #expect(fixture.inserter.expectedFields.count == 1)
        #expect(fixture.inserter.expectedFields.first.flatMap { $0 }.map { CFEqual($0, fieldG) } == true)
    }

    // MARK: - AC-9

    @Test("AC-9: フォーカスが移っていて挿入しなかったときは、パネルが開き直して文章が戻り、挿入先が外れて合図が1回増え、知らせが1回出る")
    func focusMovedReopensWithNotice() async {
        await expectReopenedWithNotice(shouldSend: false)
    }

    // MARK: - AC-10

    @Test("AC-10: 確定+送信でフォーカスが移っていたときも、同じ戻り方と同じ知らせになる")
    func focusMovedWithSendReopensWithSameNotice() async {
        await expectReopenedWithNotice(shouldSend: true)
    }
}
