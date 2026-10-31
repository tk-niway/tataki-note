import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelCommitFlowTests {
    private static let ownPid: pid_t = 4242

    private let other = InsertionTarget(processIdentifier: 7001, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let field = AXUIElementCreateApplication(pid_t.max)

    @MainActor
    private final class Fixture {
        enum Event: Equatable {
            case emptyInput
            case returnInput
            case hide
            case reopen
            case insertionRequested(String, InsertionTarget, Bool)
        }

        let model = PanelModel()
        let library = DraftLibrary(store: .inMemory)
        let session: DraftSession
        let permission: PermissionStub
        let inserter = InserterStub(result: .inserted)
        let probe = FocusedElementProbeStub()
        let monitor: InsertionTargetMonitor
        let sizing = PanelSizing()
        let flow: PanelCommitFlow
        private(set) var events: [Event] = []
        private(set) var noticeMessages: [String] = []

        init(isTrusted: Bool = true, target: InsertionTarget?, field: AXUIElement) {
            permission = PermissionStub(isTrusted: isTrusted)
            session = DraftSession(panel: model, library: library, ownProcessIdentifier: PanelCommitFlowTests.ownPid)
            probe.result = FocusedElementProbe(
                element: field,
                lookup: WatcherFixture.textFieldLookup,
                frame: CGRect(x: 0, y: 0, width: 100, height: 20)
            )
            probe.elementFrame = CGRect(x: 0, y: 0, width: 100, height: 20)
            monitor = InsertionTargetMonitor.testFactory(
                probe: probe,
                ownProcessIdentifier: PanelCommitFlowTests.ownPid
            )(model)
            flow = PanelCommitFlow(
                model: model,
                session: session,
                library: library,
                permission: permission,
                inserter: inserter,
                targetMonitor: monitor,
                sizing: sizing,
                ownProcessIdentifier: PanelCommitFlowTests.ownPid
            )
            flow.onEmptyInput = { [weak self] in self?.events.append(.emptyInput) }
            flow.onReturnInput = { [weak self] in self?.events.append(.returnInput) }
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
    }

    private func waitFor(_ condition: () -> Bool) async {
        _ = try? await waitUntil(attempts: 300, interval: .milliseconds(10), condition)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    // MARK: - AC-8

    @Test("AC-8: 本文が空の確定は、空の知らせだけで、隠さず、挿入も入力欄の確かめもしない")
    func emptyTextOnlySignalsEmptyInput() async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        let framesBefore = fixture.probe.frameRequests.count

        fixture.flow.commit(shouldSendAfterInsert: false)
        await settle()

        #expect(fixture.events == [.emptyInput])
        #expect(fixture.model.isPresented)
        #expect(fixture.probe.frameRequests.count == framesBefore)
        #expect(fixture.inserter.calls.isEmpty)
    }

    @Test("AC-8: 覚えている入力欄が読めないと、挿入先を外して「挿入先なし」を知らせ、入力をパネルへ戻し、隠さず挿入しない")
    func unreadableFieldReturnsInputWithoutHiding() async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.model.text = "hello"
        #expect(fixture.model.target == other)
        fixture.probe.elementFrame = nil
        let alertsBefore = fixture.model.noTargetAlertCount

        fixture.flow.commit(shouldSendAfterInsert: false)
        await settle()

        #expect(fixture.events == [.returnInput])
        #expect(fixture.model.target == nil)
        #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        #expect(fixture.model.isPresented)
        #expect(fixture.model.text == "hello")
        #expect(fixture.inserter.calls.isEmpty)
    }

    @Test("AC-8: 挿入先なしの確定は、合図が1回増えるだけで、隠さず挿入もしない")
    func noTargetDoesNothingElse() async {
        let fixture = Fixture(target: nil, field: field)
        defer { fixture.finish() }
        fixture.model.text = "draft"
        let alertsBefore = fixture.model.noTargetAlertCount

        fixture.flow.commit(shouldSendAfterInsert: true)
        await settle()

        #expect(fixture.events.isEmpty)
        #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        #expect(fixture.model.isPresented)
        #expect(fixture.inserter.calls.isEmpty)
    }

    @Test("AC-8: 挿入できるときは、隠してから挿入先・送信するかを知らせ、その文章で1回挿入し、保存した大きさを捨てる", arguments: [false, true])
    func insertsAfterHiding(shouldSend: Bool) async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.model.text = "hello\nworld"
        fixture.sizing.userDidResize(from: CGSize(width: 520, height: 340), to: CGSize(width: 640, height: 400))
        #expect(fixture.sizing.heldSize != nil)

        fixture.flow.commit(shouldSendAfterInsert: shouldSend)
        await waitFor { !fixture.inserter.calls.isEmpty && fixture.sizing.heldSize == nil }

        #expect(fixture.events == [.hide, .insertionRequested("hello\nworld", other, shouldSend)])
        #expect(fixture.model.isPresented == false)
        #expect(fixture.inserter.calls.count == 1)
        #expect(fixture.inserter.calls.first?.text == "hello\nworld")
        #expect(fixture.inserter.calls.first?.target == other)
        #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
        #expect(fixture.sizing.heldSize == nil)
        #expect(fixture.library.history.count == 1)
    }

    @Test("AC-8: 挿入できずに本文が残っていれば、パネルを開き直し、挿入先なしにして合図を1回増やす", arguments: [InsertionResult.noTextInput, .targetNotActivated])
    func reopensWhenInsertionFails(result: InsertionResult) async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = result
        fixture.model.text = "committed"
        let alertsBefore = fixture.model.noTargetAlertCount

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { fixture.events.contains(.reopen) && fixture.model.noTargetAlertCount > alertsBefore }

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, false), .reopen])
        #expect(fixture.model.isPresented)
        #expect(fixture.model.text == "committed")
        #expect(fixture.model.target == nil)
        #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-11: 挿入できなかったときは、開き直しても知らせを出さない", arguments: [InsertionResult.noTextInput, .targetNotActivated])
    func notInsertedReopensWithoutNotice(result: InsertionResult) async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = result
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: true)
        await waitFor { fixture.events.contains(.reopen) }
        await settle()

        #expect(fixture.events.contains(.reopen))
        #expect(fixture.noticeMessages.isEmpty)
    }

    // MARK: - 文章が入ったのを確かめられなかったとき

    @Test("AC-9: 確かめられなかったら、パネルを開き直して文章を戻し、挿入先なしにして合図を1回増やし、大きさを残し、送信の有無に応じた文で1回知らせる", arguments: [false, true])
    func reopensWhenPasteNotConfirmed(shouldSend: Bool) async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = .pasteNotConfirmed
        fixture.model.text = "committed"
        fixture.sizing.userDidResize(from: CGSize(width: 520, height: 340), to: CGSize(width: 640, height: 400))
        let heldSize = fixture.sizing.heldSize
        #expect(heldSize != nil)
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
        #expect(fixture.noticeMessages == [shouldSend ? PanelCommitFlow.notConfirmedSentMessage : PanelCommitFlow.notConfirmedInsertedMessage])
    }

    @Test("AC-9: 確かめられなくても、その間に新しい文章を書き始めていれば、開き直さず、挿入先も外さず、知らせない")
    func pasteNotConfirmedDoesNothingOverNewText() async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = .pasteNotConfirmed
        fixture.inserter.onInsert = { [model = fixture.model] in model.text = "new" }
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: true)
        await waitFor { !fixture.inserter.calls.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, true)])
        #expect(fixture.model.text == "new")
        #expect(fixture.model.noTargetAlertCount == 0)
        #expect(fixture.noticeMessages.isEmpty)
    }

    @Test("AC-9: 確かめている間にパネルを開き直していて本文が空なら、開き直さずに文章を戻し、挿入先を外して合図を1回増やし、知らせる", arguments: [false, true])
    func pasteNotConfirmedOverReopenedPanelRejectsTarget(shouldSend: Bool) async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = .pasteNotConfirmed
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
        #expect(fixture.noticeMessages == [shouldSend ? PanelCommitFlow.notConfirmedSentMessage : PanelCommitFlow.notConfirmedInsertedMessage])
    }

    @Test("AC-11: 挿入できなかったときは、確かめている間にパネルを開き直していても、文章は戻るが挿入先は外さず、合図も知らせも出さない")
    func notInsertedOverReopenedPanelKeepsTarget() async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = .targetNotActivated
        fixture.inserter.onInsert = { [model = fixture.model, other] in model.present(target: other) }
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { !fixture.inserter.calls.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, false)])
        #expect(fixture.model.text == "committed")
        #expect(fixture.model.target == other)
        #expect(fixture.model.noTargetAlertCount == 0)
        #expect(fixture.noticeMessages.isEmpty)
    }

    @Test("AC-11: 知らせる文は、確かめられなかったときだけ、送信の有無に応じて返る")
    func noticeTable() {
        let cases: [(CommitOutcome, Bool, String?)] = [
            (.inserted, false, nil),
            (.inserted, true, nil),
            (.insertedIntoSecureField, false, nil),
            (.insertedIntoSecureField, true, nil),
            (.notInserted, false, nil),
            (.notInserted, true, nil),
            (.notConfirmed, false, PanelCommitFlow.notConfirmedInsertedMessage),
            (.notConfirmed, true, PanelCommitFlow.notConfirmedSentMessage),
        ]
        for (outcome, shouldSend, expected) in cases {
            #expect(PanelCommitFlow.notice(for: outcome, shouldSendAfterInsert: shouldSend) == expected)
        }
        #expect(PanelCommitFlow.notConfirmedSentMessage == "送信できませんでした")
        #expect(PanelCommitFlow.notConfirmedInsertedMessage == "挿入できませんでした")
    }

    @Test("AC-11: パネルの戻し方は、結果・パネルが開いているか・文章が戻ったかで決まる")
    func recoveryTable() {
        typealias Recovery = PanelCommitFlow.FailureRecovery
        let cases: [(CommitOutcome, Bool, Bool, Recovery)] = [
            (.notInserted, false, true, .reopen),
            (.notInserted, true, true, .none),
            (.notInserted, false, false, .none),
            (.notInserted, true, false, .none),
            (.notConfirmed, false, true, .reopen),
            (.notConfirmed, true, true, .rejectTarget),
            (.notConfirmed, false, false, .none),
            (.notConfirmed, true, false, .none),
            (.inserted, false, true, .none),
            (.inserted, true, true, .none),
            (.inserted, false, false, .none),
            (.inserted, true, false, .none),
            (.insertedIntoSecureField, false, true, .none),
            (.insertedIntoSecureField, true, true, .none),
            (.insertedIntoSecureField, false, false, .none),
            (.insertedIntoSecureField, true, false, .none),
        ]
        for (outcome, isPresented, isTextRestored, expected) in cases {
            #expect(PanelCommitFlow.recovery(for: outcome, isPresented: isPresented, isTextRestored: isTextRestored) == expected)
        }
    }

    @Test("AC-8: 挿入できなくても、その間に新しい文章を書き始めていれば、開き直さない")
    func doesNotReopenOverNewText() async {
        let fixture = Fixture(target: other, field: field)
        defer { fixture.finish() }
        fixture.inserter.result = .targetNotActivated
        fixture.inserter.onInsert = { [model = fixture.model] in model.text = "new" }
        fixture.model.text = "committed"

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { !fixture.inserter.calls.isEmpty }
        await settle()

        #expect(fixture.events == [.hide, .insertionRequested("committed", other, false)])
        #expect(fixture.model.text == "new")
        #expect(fixture.model.noTargetAlertCount == 0)
    }

    @Test("AC-8: 許可が無い確定は、位置を読まずに隠し、案内を開く処理を1回呼び、挿入せず文章を残す")
    func permissionDeniedHidesAndOpensGuide() async {
        let fixture = Fixture(isTrusted: false, target: other, field: field)
        defer { fixture.finish() }
        var guideOpenCount = 0
        fixture.flow.onPermissionDenied = { guideOpenCount += 1 }
        fixture.model.text = "draft"
        let framesBefore = fixture.probe.frameRequests.count

        fixture.flow.commit(shouldSendAfterInsert: false)
        await waitFor { guideOpenCount > 0 }

        #expect(fixture.events == [.hide])
        #expect(guideOpenCount == 1)
        #expect(fixture.probe.frameRequests.count == framesBefore)
        #expect(fixture.inserter.calls.isEmpty)
        #expect(fixture.model.text == "draft")
    }
}
