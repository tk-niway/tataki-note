import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class FrontApplicationBox {
    var app: InsertionTarget?
}

@MainActor
struct PanelControllerInsertionCheckTests {
    private static let ownPid: pid_t = 4242

    private let own = InsertionTarget(processIdentifier: PanelControllerInsertionCheckTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
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
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.animationMode = .off
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
        let controller = PanelControllerFactory.make(
            settings: settings,
            probe: probe,
            inserter: inserter,
            permission: permission,
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

    // MARK: - AC-11

    @Test("AC-11: 挿入先なしで確定・確定+送信すると、パネルは開いたまま文章もそのままで、挿入も入力欄の確かめもされず、合図が1回増え、履歴に残らない", arguments: [false, true])
    func noTargetCommitKeepsPanelOpen(shouldSend: Bool) async throws {
        try await withFixture(target: nil) { fixture in
            openWithText(fixture, "draft")
            #expect(fixture.model.target == nil)
            let alertsBefore = fixture.model.noTargetAlertCount
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit(shouldSendAfterInsert: shouldSend)
            await settle()

            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "draft")
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
            #expect(fixture.probe.frameRequests.count == framesBefore)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.library.history.isEmpty)
        }
    }

    // MARK: - AC-12

    @Test("AC-12: 他のアプリが挿入先の確定では、入力欄の位置を同期で1回読み、読めればその場でパネルが閉じて、その文章・挿入先・送信の有無で1回挿入する", arguments: [false, true])
    func otherAppCommitReadsFieldOnceThenCloses(shouldSend: Bool) async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            #expect(fixture.model.target == other)
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit(shouldSendAfterInsert: shouldSend)

            #expect(fixture.probe.frameRequests.count == framesBefore + 1)
            #expect(fixture.model.isPresented == false)
            await waitFor { !fixture.inserter.calls.isEmpty }
            await settle()

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "hello\nworld")
            #expect(fixture.inserter.calls.first?.target == other)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
        }
    }

    @Test("AC-12: 入力欄の位置がもともと読めないアプリでも、確定ではそのままパネルが閉じて挿入される")
    func neverReadableFieldStillInserts() async throws {
        try await withFixture(target: other) { fixture in
            fixture.probe.elementFrame = nil
            openWithText(fixture)
            fixture.monitor.refresh()
            #expect(fixture.model.target == other)

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            await waitFor { !fixture.inserter.calls.isEmpty }
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.model.noTargetAlertCount == 0)
        }
    }

    @Test("AC-12, AC-17, AC-18: 閉じる前に入力欄の位置を読むのは、文章があり・許可があり・挿入先が自分以外のときだけ")
    func shouldCheckTrackedFieldRules() {
        let ownPid = Self.ownPid
        #expect(PanelController.shouldCheckTrackedField(target: other, text: "a", isTrusted: true, ownProcessIdentifier: ownPid))
        #expect(!PanelController.shouldCheckTrackedField(target: own, text: "a", isTrusted: true, ownProcessIdentifier: ownPid))
        #expect(!PanelController.shouldCheckTrackedField(target: nil, text: "a", isTrusted: true, ownProcessIdentifier: ownPid))
        #expect(!PanelController.shouldCheckTrackedField(target: other, text: "", isTrusted: true, ownProcessIdentifier: ownPid))
        #expect(!PanelController.shouldCheckTrackedField(target: other, text: "a", isTrusted: false, ownProcessIdentifier: ownPid))
    }

    // MARK: - AC-13

    @Test("AC-13: 覚えている入力欄の位置が読めないと分かると、パネルは開いたまま文章もそのままで挿入せず、挿入先なしになり、合図とフォーカスの要求が1回増える")
    func unreadableFieldKeepsPanelOpen() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            fixture.probe.elementFrame = nil
            #expect(fixture.model.target == other)
            let alertsBefore = fixture.model.noTargetAlertCount
            let focusBefore = fixture.model.focusRequest

            fixture.controller.commit()
            await settle()

            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.model.target == nil)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-13: 位置が読めなくて外れた入力欄は、フォーカスが移っても挿入先に戻らず、クリックで選び直されると挿入先に戻る")
    func rejectedFieldReturnsOnlyWhenClicked() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            fixture.probe.elementFrame = nil
            fixture.controller.commit()
            #expect(fixture.model.noTargetAlertCount == 1)
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

    @Test("AC-4: 挿入先を前面にできなかったという結果でも、文章が戻ってパネルが開き直され、挿入先なしになって合図が1回増える")
    func targetNotActivatedReopensPanel() async throws {
        try await withFixture(target: other) { fixture in
            fixture.inserter.result = .targetNotActivated
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

    @Test("AC-16: 確定キーを続けて押しても、位置を読むのも挿入も1回だけで、2回目は何も入れない")
    func repeatedCommitInsertsOnce() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit()
            fixture.controller.commit(shouldSendAfterInsert: true)
            fixture.controller.commit()
            await waitFor { !fixture.inserter.calls.isEmpty }
            await settle()

            #expect(fixture.probe.frameRequests.count == framesBefore + 1)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == false)
        }
    }

    @Test("AC-16: 見張りがすでに挿入先なしにしていれば、位置を読み直さず、挿入せずに合図が1回増え、パネルは開いたまま")
    func targetAlreadyLostSignalsWithoutReadingAgain() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            fixture.probe.elementFrame = nil
            fixture.monitor.refresh()
            #expect(fixture.model.target == nil)
            let alertsBefore = fixture.model.noTargetAlertCount
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit()
            await settle()

            #expect(fixture.probe.frameRequests.count == framesBefore)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello\nworld")
            #expect(fixture.model.noTargetAlertCount == alertsBefore + 1)
        }
    }

    @Test("AC-16: 位置を読む確定の後にパネルを閉じて開き直しても、また確定すれば挿入される")
    func commitWorksAgainAfterReopening() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture)
            fixture.monitor.refresh()
            fixture.probe.elementFrame = nil
            fixture.controller.commit()
            #expect(fixture.model.target == nil)

            fixture.controller.close()
            fixture.probe.elementFrame = CGRect(x: 0, y: 0, width: 100, height: 20)
            fixture.controller.open()
            fixture.monitor.refresh()
            #expect(fixture.model.target == other)
            fixture.controller.commit()
            await waitFor { !fixture.inserter.calls.isEmpty }

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "hello\nworld")
        }
    }

    // MARK: - AC-17

    @Test("AC-17: TatakiNote 自身が挿入先の確定は、入力欄の位置を読まずにその場でパネルが閉じて挿入される")
    func ownTargetCommitClosesImmediately() async throws {
        try await withFixture(target: own) { fixture in
            openWithText(fixture, "practice")
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            #expect(fixture.probe.frameRequests.count == framesBefore)
            await waitFor { !fixture.inserter.calls.isEmpty }
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "practice")
            #expect(fixture.inserter.calls.first?.target == own)
        }
    }

    // MARK: - AC-18

    @Test("AC-18: 許可が無いときの確定は、挿入先があっても位置を読まず、案内を開く処理が呼ばれてパネルが閉じ、文章は残る")
    func permissionDeniedClosesWithGuide() async throws {
        try await withFixture(isTrusted: false, target: other) { fixture in
            var guideOpenCount = 0
            fixture.controller.onPermissionDenied = { guideOpenCount += 1 }
            openWithText(fixture, "draft")
            let framesBefore = fixture.probe.frameRequests.count

            fixture.controller.commit()

            #expect(fixture.model.isPresented == false)
            #expect(fixture.probe.frameRequests.count == framesBefore)
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

    @Test("文章が空の確定は、挿入先があってもなくても位置を読まず、パネルは閉じない")
    func emptyTextCommitKeepsPanelOpen() async throws {
        for target in [other, nil] as [InsertionTarget?] {
            try await withFixture(target: target) { fixture in
                fixture.controller.open()
                let framesBefore = fixture.probe.frameRequests.count

                fixture.controller.commit()

                #expect(fixture.model.isPresented)
                #expect(fixture.probe.frameRequests.count == framesBefore)
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

    // MARK: - AC-21 〜 AC-24

    @Test("AC-21: ノートの書きかけで他のアプリの入力欄をクリックすると、挿入先はそのアプリに移り、フォーカスの要求は増えず、パネルは開いたまま")
    func adoptingFieldInNoteKeepsInputInOtherApp() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            fixture.controller.session.toggleMode()
            #expect(fixture.controller.session.mode == .note)
            #expect(fixture.model.target == other)
            let focusBefore = fixture.model.focusRequest

            fixture.front.app = another
            fixture.monitor.handleClick()
            await settle()

            #expect(fixture.model.target == another)
            #expect(fixture.model.focusRequest == focusBefore)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-21: ノートの書きかけで、確かめ直しのときに入力欄が見つかって挿入先が移っても、フォーカスの要求は増えない")
    func recheckAdoptingFieldInNoteKeepsInputInOtherApp() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            fixture.controller.session.toggleMode()
            let focusBefore = fixture.model.focusRequest

            fixture.probe.result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
            fixture.front.app = another
            fixture.monitor.handleClick()
            fixture.probe.result = FocusedElementProbe(element: fieldB, lookup: WatcherFixture.textFieldLookup, frame: nil)
            await settle()

            #expect(fixture.model.target == another)
            #expect(fixture.model.focusRequest == focusBefore)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-22: インサートの書きかけで他のアプリの入力欄をクリックすると、今どおりフォーカスの要求が1回増える")
    func adoptingFieldInInsertReturnsFocusToPanel() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            #expect(fixture.controller.session.mode == .insert)
            let focusBefore = fixture.model.focusRequest

            fixture.front.app = another
            fixture.monitor.handleClick()

            #expect(fixture.model.target == another)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-22: ノートの書きかけで確かめ直しの前にインサートにすると、確かめ直しで移ったときはそのときのモードで戻す")
    func recheckAdoptingFieldUsesModeAtThatTime() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            fixture.controller.session.toggleMode()
            let focusBefore = fixture.model.focusRequest

            fixture.probe.result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
            fixture.front.app = another
            fixture.monitor.handleClick()
            fixture.controller.session.toggleMode()
            fixture.probe.result = FocusedElementProbe(element: fieldB, lookup: WatcherFixture.textFieldLookup, frame: nil)
            await settle()

            #expect(fixture.controller.session.mode == .insert)
            #expect(fixture.model.target == another)
            #expect(fixture.model.focusRequest == focusBefore + 1)
        }
    }

    @Test("AC-22: 入力欄が移ったときに入力を戻すのはインサートの書きかけだけ")
    func onlyInsertReturnsInputAfterFieldAdopted() {
        #expect(PanelController.shouldReturnInputAfterFieldAdopted(mode: .insert))
        #expect(!PanelController.shouldReturnInputAfterFieldAdopted(mode: .note))
    }

    @Test("AC-23: ノートで他のアプリの入力欄をクリックした後に、インサートにして確定すると、クリックしたアプリへ1回挿入される")
    func commitAfterAdoptingFieldInNoteInsertsIntoClickedApp() async throws {
        try await withFixture(target: other) { fixture in
            openWithText(fixture, "memo")
            fixture.controller.session.toggleMode()
            fixture.front.app = another
            fixture.monitor.handleClick()
            await settle()
            #expect(fixture.model.target == another)

            fixture.controller.session.toggleMode()
            fixture.controller.commit()
            await waitFor { !fixture.inserter.calls.isEmpty }
            await settle()

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "memo")
            #expect(fixture.inserter.calls.first?.target == another)
        }
    }

    @Test("AC-24: ノートで他のアプリの入力欄をクリックした後でも、ホットキー(toggle)でパネルが閉じる")
    func toggleClosesPanelAfterAdoptingFieldInNote() async throws {
        try await withFixture(target: other) { fixture in
            fixture.controller.open()
            fixture.controller.session.toggleMode()
            fixture.front.app = another
            fixture.monitor.handleClick()
            await settle()
            #expect(fixture.model.target == another)
            #expect(fixture.model.isPresented)

            fixture.controller.toggle()

            #expect(!fixture.model.isPresented)
        }
    }
}
