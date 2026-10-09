import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class ReadinessGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FrontApplicationBox {
    var app: InsertionTarget?
}

@MainActor
private final class MonitorBox {
    var monitor: InsertionTargetMonitor?
}

@MainActor
struct PanelInsertionCheckTests {
    private static let ownPid: pid_t = 4242

    private let own = InsertionTarget(processIdentifier: PanelInsertionCheckTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: 7001, bundleIdentifier: "com.example.Other", localizedName: "Other")
    private let another = InsertionTarget(processIdentifier: 7002, bundleIdentifier: "com.example.Another", localizedName: "Another")
    private let fieldA = AXUIElementCreateApplication(pid_t.max)
    private let fieldB = AXUIElementCreateApplication(pid_t.max - 1)

    @MainActor
    private struct Fixture {
        let controller: PanelController
        let probe: FocusedElementProbeStub
        let inserter: InserterStub
        let library: DraftLibrary
        let front: FrontApplicationBox
        let monitor: InsertionTargetMonitor
        let permission: PermissionStub

        var model: PanelModel { controller.model }
    }

    private func withFixture(
        isTrusted: Bool = true,
        target: InsertionTarget?,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.isPanelAnimationEnabled = false
        let probe = FocusedElementProbeStub()
        probe.result = FocusedElementProbe(element: fieldA, lookup: WatcherFixture.textFieldLookup, frame: nil)
        probe.elementFrame = CGRect(x: 0, y: 0, width: 100, height: 20)
        let inserter = InserterStub(result: .inserted)
        let library = DraftLibrary(store: .inMemory)
        let permission = PermissionStub(isTrusted: isTrusted)
        let front = FrontApplicationBox()
        let monitorBox = MonitorBox()
        let factory = InsertionTargetMonitor.testFactory(
            probe: probe,
            ownProcessIdentifier: Self.ownPid,
            frontmostApplication: { front.app }
        )
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: permission,
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: library,
            makeTargetMonitor: { model in
                let monitor = factory(model)
                monitorBox.monitor = monitor
                return monitor
            }
        )
        if let target {
            controller.targetOverride = { target }
        } else {
            controller.isTargetLookupDisabled = true
        }
        defer { controller.close() }
        let monitor = try #require(monitorBox.monitor)
        try await body(
            Fixture(
                controller: controller,
                probe: probe,
                inserter: inserter,
                library: library,
                front: front,
                monitor: monitor,
                permission: permission
            )
        )
    }

    private func openWithText(_ fixture: Fixture, _ text: String = "hello\nworld") {
        fixture.controller.open()
        fixture.model.text = text
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    private func waitFor(_ condition: () -> Bool) async {
        _ = try? await waitUntil(attempts: 300, interval: .milliseconds(10), condition)
    }

    private func waitUntilGateIsWaiting(_ gate: ReadinessGate) async {
        await waitFor { gate.isWaiting }
    }

    // MARK: - AC-11

    @Test("AC-11: 挿入先なしで確定・確定+送信すると、パネルは開いたまま文章もそのままで、挿入も確かめもされず、合図が1回増え、履歴に残らない", arguments: [false, true])
    func noTargetCommitKeepsPanelOpen(shouldSend: Bool) async throws {
        try await withFixture(target: nil) { fixture in
            openWithText(fixture, "draft")
            #expect(fixture.model.target == nil)
            let alertsBefore = fixture.model.noTargetAlertCount

            fixture.controller.commit(shouldSendAfterInsert: shouldSend)
            await settle()

            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "draft")
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
            #expect(fixture.inserter.readinessChecks.isEmpty)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.library.history.isEmpty)
        }
    }

    // MARK: - AC-12

    @Test("AC-12: 他のアプリが挿入先の確定では、確かめが済むまでパネルは閉じず挿入もせず、通ると閉じてその文章・挿入先・送信の有無で1回挿入する", arguments: [false, true])
    func otherAppCommitChecksBeforeClosing(shouldSend: Bool) async throws {
        try await withFixture(target: other) { fixture in
            let gate = ReadinessGate()
            fixture.inserter.onCheckReadiness = { await gate.wait() }
            openWithText(fixture)
            #expect(fixture.model.target == other)

            fixture.controller.commit(shouldSendAfterInsert: shouldSend)
            await waitUntilGateIsWaiting(gate)

            #expect(fixture.inserter.readinessChecks == [other])
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.inserter.calls.isEmpty)

            gate.release()
            await waitFor { !fixture.inserter.calls.isEmpty }

            #expect(fixture.model.isPresented == false)
            #expect(fixture.inserter.readinessChecks.count == 1)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "hello\nworld")
            #expect(fixture.inserter.calls.first?.target == other)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
        }
    }

    @Test("AC-12, AC-17, AC-18: 閉じる前に確かめるのは、文章があり・許可があり・挿入先が自分以外のときだけ")
    func insertionTargetToCheckRules() {
        let ownPid = Self.ownPid
        #expect(PanelController.insertionTargetToCheck(target: other, text: "a", isTrusted: true, ownProcessIdentifier: ownPid) == other)
        #expect(PanelController.insertionTargetToCheck(target: own, text: "a", isTrusted: true, ownProcessIdentifier: ownPid) == nil)
        #expect(PanelController.insertionTargetToCheck(target: nil, text: "a", isTrusted: true, ownProcessIdentifier: ownPid) == nil)
        #expect(PanelController.insertionTargetToCheck(target: other, text: "", isTrusted: true, ownProcessIdentifier: ownPid) == nil)
        #expect(PanelController.insertionTargetToCheck(target: other, text: "a", isTrusted: false, ownProcessIdentifier: ownPid) == nil)
    }

    // MARK: - AC-13

    @Test("AC-13: 確かめで前面にできない・入力欄が選ばれていないと分かると、パネルは開いたまま文章もそのままで挿入せず、挿入先なしになり、合図とフォーカスの要求が1回増える", arguments: [InsertionReadiness.targetNotActivated, .noTextInput])
    func failedCheckKeepsPanelOpen(readiness: InsertionReadiness) async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.readiness = readiness
            openWithText(fixture)
            let alertsBefore = fixture.model.noTargetAlertCount
            let focusBefore = fixture.model.focusRequest

            fixture.controller.commit()
            await waitFor { fixture.model.noTargetAlertCount > alertsBefore }

            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.model.target == nil)
            #expect(fixture.inserter.readinessChecks == [other])
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-13: 確かめで外れた入力欄は、フォーカスが移っても挿入先に戻らず、クリックで選び直されるまで戻らない")
    func rejectedFieldReturnsOnlyWhenClicked() async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.readiness = .noTextInput
            openWithText(fixture)
            fixture.controller.commit()
            await waitFor { fixture.model.noTargetAlertCount > 0 }
            #expect(fixture.model.target == nil)

            fixture.monitor.refresh()
            #expect(fixture.model.target == nil)

            fixture.probe.result = FocusedElementProbe(element: fieldB, lookup: WatcherFixture.textFieldLookup, frame: nil)
            fixture.monitor.refresh()
            #expect(fixture.model.target == nil)

            fixture.front.app = other
            fixture.monitor.handleClick()
            #expect(fixture.model.target == other)
        }
    }

    @Test("AC-13: 確かめで外れた入力欄は、クリックで選び直されると挿入先に戻る")
    func rejectedFieldReturnsWhenClicked() async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.readiness = .targetNotActivated
            openWithText(fixture)
            fixture.controller.commit()
            await waitFor { fixture.model.noTargetAlertCount > 0 }
            #expect(fixture.model.target == nil)

            fixture.front.app = other
            fixture.monitor.handleClick()

            #expect(fixture.model.target == other)
        }
    }

    // MARK: - AC-15

    @Test("AC-15: 確かめの後の貼り付けで挿入できなかったときは、文章が戻ってパネルが開き直され、挿入先なしになって合図が1回増える")
    func failedInsertionReopensPanel() async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.result = .noTextInput
            openWithText(fixture, "committed")
            let alertsBefore = fixture.model.noTargetAlertCount

            fixture.controller.commit()
            await waitFor { fixture.model.noTargetAlertCount > alertsBefore }

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "committed")
            #expect(fixture.model.target == nil)
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        }
    }

    @Test("AC-15: 貼り付けに失敗する間に新しい文章を書き始めていれば、開き直さない")
    func failedInsertionDoesNotReopenOverNewText() async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.result = .targetNotActivated
            fixture.inserter.onInsert = { [model = fixture.model] in model.text = "new" }
            openWithText(fixture, "committed")

            fixture.controller.commit()
            await waitFor { !fixture.inserter.calls.isEmpty }
            await settle()

            #expect(fixture.model.isPresented == false)
            #expect(fixture.model.text == "new")
            #expect(fixture.model.noTargetAlertCount == 0)
        }
    }

    // MARK: - AC-16

    @Test("AC-16: 確かめの途中で確定キーをもう一度押しても、確かめと挿入は1回だけ")
    func commitDuringCheckIsIgnored() async throws {
        try await withFixture(target: other) { fixture in
            let gate = ReadinessGate()
            fixture.inserter.onCheckReadiness = { await gate.wait() }
            openWithText(fixture)

            fixture.controller.commit()
            await waitUntilGateIsWaiting(gate)
            fixture.controller.commit(shouldSendAfterInsert: true)
            fixture.controller.commit()
            gate.release()
            await waitFor { !fixture.inserter.calls.isEmpty }
            await settle()

            #expect(fixture.inserter.readinessChecks.count == 1)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == false)
        }
    }

    @Test("AC-16: 確かめの途中にパネルを閉じると、確かめの結果では何も起きず、開き直せばまた確定できる")
    func closingDuringCheckDiscardsResult() async throws {
        try await withFixture(target: other) { fixture in
            let gate = ReadinessGate()
            fixture.inserter.onCheckReadiness = { await gate.wait() }
            openWithText(fixture)

            fixture.controller.commit()
            await waitUntilGateIsWaiting(gate)
            fixture.controller.close()
            await settle()
            gate.release()
            await settle()

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented == false)
            #expect(fixture.model.noTargetAlertCount == 0)
            #expect(fixture.model.text == "hello\nworld")

            fixture.inserter.onCheckReadiness = nil
            fixture.controller.open()
            fixture.controller.commit()
            await waitFor { !fixture.inserter.calls.isEmpty }

            #expect(fixture.inserter.readinessChecks.count == 2)
            #expect(fixture.inserter.calls.count == 1)
        }
    }

    @Test("AC-16: 確かめの途中で挿入先なしに変わると、挿入せず合図が1回増え、パネルへフォーカスを戻す")
    func targetLostDuringCheckSignalsNoTarget() async throws {
        try await withFixture(target: other) { fixture in
            let gate = ReadinessGate()
            fixture.inserter.onCheckReadiness = { await gate.wait() }
            openWithText(fixture)
            let alertsBefore = fixture.model.noTargetAlertCount
            let focusBefore = fixture.model.focusRequest

            fixture.controller.commit()
            await waitUntilGateIsWaiting(gate)
            fixture.monitor.refresh()
            #expect(fixture.model.target == other)
            fixture.probe.elementFrame = nil
            fixture.monitor.refresh()
            #expect(fixture.model.target == nil)
            gate.release()
            await waitFor { fixture.model.noTargetAlertCount > alertsBefore }
            await settle()

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-16: 確かめの途中で別のアプリへ選び直されると、挿入も合図もしない")
    func switchingAppDuringCheckDiscardsResult() async throws {
        try await withFixture(target: other) { fixture in
            let gate = ReadinessGate()
            fixture.inserter.onCheckReadiness = { await gate.wait() }
            openWithText(fixture)
            let alertsBefore = fixture.model.noTargetAlertCount

            fixture.controller.commit()
            await waitUntilGateIsWaiting(gate)
            fixture.front.app = another
            fixture.monitor.handleClick()
            #expect(fixture.model.target == another)
            gate.release()
            await settle()

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.model.noTargetAlertCount == alertsBefore)
            #expect(fixture.model.target == another)
        }
    }

    // MARK: - AC-17

    @Test("AC-17: TatakiNote 自身が挿入先の確定は、確かめをせずにその場でパネルが閉じて挿入される")
    func ownTargetCommitClosesImmediately() async throws {
        try await withFixture(target: own) { fixture in
            openWithText(fixture, "practice")

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            #expect(fixture.inserter.readinessChecks.isEmpty)
            await waitFor { !fixture.inserter.calls.isEmpty }
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "practice")
            #expect(fixture.inserter.calls.first?.target == own)
        }
    }

    // MARK: - AC-18

    @Test("AC-18: 許可が無いときの確定は、挿入先があっても確かめず、案内を開く処理が呼ばれてパネルが閉じ、文章は残る")
    func permissionDeniedClosesWithGuide() async throws {
        try await withFixture(isTrusted: false, target: other) { fixture in
            var guideOpenCount = 0
            fixture.controller.onPermissionDenied = { guideOpenCount += 1 }
            openWithText(fixture, "draft")

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            #expect(fixture.inserter.readinessChecks.isEmpty)
            await waitFor { guideOpenCount > 0 }
            #expect(guideOpenCount == 1)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.text == "draft")
        }
    }

    @Test("AC-18: 許可が無いときの確定は、挿入先なしでも案内を開いてパネルが閉じ、文章は残る")
    func permissionDeniedWithoutTargetClosesWithGuide() async throws {
        try await withFixture(isTrusted: false, target: nil) { fixture in
            var guideOpenCount = 0
            fixture.controller.onPermissionDenied = { guideOpenCount += 1 }
            openWithText(fixture, "draft")

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            await waitFor { guideOpenCount > 0 }
            #expect(guideOpenCount == 1)
            #expect(fixture.model.text == "draft")
            #expect(fixture.model.noTargetAlertCount == 0)
        }
    }

    @Test("AC-18: 文章が空の確定は、挿入先があってもなくても確かめずにパネルが閉じる")
    func emptyTextCommitClosesPanel() async throws {
        for target in [other, nil] as [InsertionTarget?] {
            try await withFixture(target: target) { fixture in
                fixture.controller.open()

                fixture.controller.commit()

                #expect(fixture.model.isPresented == false)
                #expect(fixture.inserter.readinessChecks.isEmpty)
                #expect(fixture.inserter.calls.isEmpty)
                #expect(fixture.model.noTargetAlertCount == 0)
            }
        }
    }

    // MARK: - AC-28

    @Test("AC-28: 他のアプリの入力欄をクリックして挿入先が移ると、パネルの入力欄へフォーカスを戻す要求が1回増える")
    func adoptingFieldReturnsFocusToPanel() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            #expect(fixture.model.target == other)
            let focusBefore = fixture.model.focusRequest

            fixture.front.app = another
            fixture.monitor.handleClick()

            #expect(fixture.model.target == another)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-28: 入力欄でない所のクリックで挿入先なしになったときは、フォーカスを戻す要求は増えない")
    func clickOutsideFieldDoesNotReturnFocus() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            #expect(fixture.model.target == other)
            let focusBefore = fixture.model.focusRequest

            fixture.probe.result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
            fixture.front.app = other
            fixture.monitor.handleClick()
            await settle()

            #expect(fixture.model.target == nil)
            #expect(fixture.model.focusRequest == focusBefore)
        }
    }
}
