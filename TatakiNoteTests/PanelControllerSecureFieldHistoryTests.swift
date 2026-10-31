import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerSecureFieldHistoryTests {
    private static let ownPid: pid_t = 777
    private static let safari = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
    private static let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")

    @MainActor
    private struct SessionFixture {
        let panel = PanelModel()
        let library = DraftLibrary(store: .inMemory)
        let session: DraftSession

        init(target: InsertionTarget, setting: DraftMode = .note) {
            session = DraftSession(
                panel: panel,
                library: library,
                ownProcessIdentifier: PanelControllerSecureFieldHistoryTests.ownPid,
                newDraftMode: { setting }
            )
            panel.present(target: target)
        }

        func commit(text: String) -> CommitPlan {
            panel.text = text
            return session.prepareCommit { panel.prepareCommit(isAccessibilityTrusted: true) }
        }
    }

    // MARK: - パスワード欄の判定

    @Test("AC-1: subrole が AXSecureTextField の要素だけがパスワード欄で、他の subrole・subrole なし・要素なし・取得できないは違う")
    func isSecureTextFieldBoundary() {
        let secure = FocusedElementLookup.element(role: "AXTextField", subrole: "AXSecureTextField", isSelectedTextRangeSettable: true)
        let search = FocusedElementLookup.element(role: "AXTextField", subrole: "AXSearchField", isSelectedTextRangeSettable: true)
        let plain = FocusedElementLookup.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: true)

        #expect(FocusedTextInputState.isSecureTextField(secure))
        #expect(!FocusedTextInputState.isSecureTextField(search))
        #expect(!FocusedTextInputState.isSecureTextField(plain))
        #expect(!FocusedTextInputState.isSecureTextField(.noFocusedElement))
        #expect(!FocusedTextInputState.isSecureTextField(.unavailable))
    }

    @Test("AC-3: 既定の inspectFocusedInput は、入力欄の判定をそのまま返し、パスワード欄とはみなさない")
    func defaultInspectionIsNotSecure() {
        let stub = DefaultInspectorStub(state: .unknown)

        let inspection = stub.inspectFocusedInput(in: Self.safari)

        #expect(inspection == FocusedInputInspection(state: .unknown, isSecureTextField: false))
    }

    // MARK: - CommitPerformer

    @Test("AC-1, AC-3: 挿入の結果は確定の結果に引き継がれ、履歴に残すのは .inserted のときだけ")
    func performerMapsInsertionResults() async {
        let scenarios: [(InsertionResult, CommitOutcome, Bool, Bool)] = [
            (.inserted, .inserted, true, true),
            (.insertedIntoSecureField, .insertedIntoSecureField, true, false),
            (.targetNotActivated, .notInserted, false, false),
            (.noTextInput, .notInserted, false, false),
        ]
        for (insertion, expected, didInsert, recordsHistory) in scenarios {
            let model = PanelModel()
            model.present(target: Self.safari)
            model.text = "hello"
            let permission = PermissionStub(isTrusted: true)
            let performer = CommitPerformer(model: model, permission: permission, inserter: InserterStub(result: insertion))

            let outcome = await performer.perform(model.prepareCommit(isAccessibilityTrusted: true))

            #expect(outcome == expected, "\(insertion)")
            #expect(outcome.didInsert == didInsert, "\(insertion)")
            #expect(outcome.recordsHistory == recordsHistory, "\(insertion)")
        }
        #expect(CommitOutcome.notInserted.didInsert == false)
        #expect(CommitOutcome.notInserted.recordsHistory == false)
    }

    @Test("AC-2: パスワード欄に挿入できたときは、確定+送信でも文章はパネルに戻らない")
    func performerKeepsTextEmptyAfterSecureInsertion() async {
        let model = PanelModel()
        model.present(target: Self.safari)
        model.text = "secret"
        let inserter = InserterStub(result: .insertedIntoSecureField)
        let performer = CommitPerformer(model: model, permission: PermissionStub(isTrusted: true), inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: true), shouldSendAfterInsert: true)

        #expect(inserter.calls.count == 1)
        #expect(inserter.calls.first?.shouldSendAfterInsert == true)
        #expect(model.text.isEmpty)
    }

    // MARK: - DraftSession.finishCommit

    @Test("AC-1: パスワード欄に挿入できたときは、履歴にも保存した下書きの履歴にも残らない")
    func secureInsertionIsNotRecorded() {
        let fixture = SessionFixture(target: Self.safari)

        let plan = fixture.commit(text: "secret")
        fixture.session.finishCommit(plan, outcome: .insertedIntoSecureField)

        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-2: パスワード欄に挿入できたときも、パネルは空の書きかけになり、モードは新しい書きかけのものに戻る", arguments: DraftMode.allCases)
    func secureInsertionResetsDraftAndMode(setting: DraftMode) {
        let fixture = SessionFixture(target: Self.safari, setting: setting)
        fixture.session.toggleMode()
        #expect(fixture.session.mode == setting.toggled)

        let plan = fixture.commit(text: "secret")
        fixture.session.finishCommit(plan, outcome: .insertedIntoSecureField)

        #expect(fixture.session.mode == setting)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.text.isEmpty)
    }

    @Test("AC-2: 保存した下書きをパスワード欄に挿入しても、下書きは残り、パネルは空の書きかけになる")
    func secureInsertionKeepsSavedDraft() throws {
        let fixture = SessionFixture(target: Self.safari)
        fixture.panel.text = "secret"
        fixture.session.saveCurrent()
        let draft = try #require(fixture.library.drafts.first)

        let plan = fixture.commit(text: "secret")
        fixture.session.finishCommit(plan, outcome: .insertedIntoSecureField)

        #expect(fixture.library.draft(id: draft.id)?.text == "secret")
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-3: パスワード欄でない入力欄への挿入は履歴に残る")
    func ordinaryInsertionIsRecorded() throws {
        let fixture = SessionFixture(target: Self.safari)

        let plan = fixture.commit(text: "hello")
        fixture.session.finishCommit(plan, outcome: .inserted)

        let entry = try #require(fixture.library.history.first)
        #expect(fixture.library.history.count == 1)
        #expect(entry.text == "hello")
        #expect(entry.bundleIdentifier == "com.apple.Safari")
    }

    @Test("AC-3: 自分のアプリへの挿入は履歴に残らない")
    func ownAppInsertionIsNotRecorded() {
        let fixture = SessionFixture(target: Self.own)

        let plan = fixture.commit(text: "practice")
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.library.history.isEmpty)
    }

    // MARK: - PanelSizing

    @Test("AC-2: パスワード欄に挿入できたときも、ドラッグで決めた大きさは既定の大きさに戻る")
    func secureInsertionReleasesHeldSize() {
        let defaultSize = CGSize(width: 520, height: 340)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: defaultSize, hasText: true)
        sizing.userDidResize(from: defaultSize, to: CGSize(width: 700, height: 600))
        #expect(sizing.openingSize(in: visible) == CGSize(width: 700, height: 600))

        sizing.handleCommitOutcome(.insertedIntoSecureField)

        #expect(sizing.openingSize(in: visible) == defaultSize)
    }

    @Test("AC-2: 挿入できなかったときは、ドラッグで決めた大きさを保つ")
    func notInsertedKeepsHeldSize() {
        let defaultSize = CGSize(width: 520, height: 340)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let sizing = PanelSizing()
        sizing.beginOpening(defaultSize: defaultSize, hasText: true)
        sizing.userDidResize(from: defaultSize, to: CGSize(width: 700, height: 600))

        sizing.handleCommitOutcome(.notInserted)

        #expect(sizing.openingSize(in: visible) == CGSize(width: 700, height: 600))
    }

    // MARK: - パネル

    @Test("AC-2: パネルから確定してパスワード欄に挿入できたら、パネルは開き直さず、履歴に残らず、モードが戻る")
    func panelDoesNotReopenAfterSecureInsertion() async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.newDraftMode = .note
        settings.panelScreen = .main
        settings.animationMode = .off
        let inserter = InserterStub(result: .insertedIntoSecureField)
        let probe = FocusedElementProbeStub()
        probe.result = FocusedElementProbe(
            element: AXUIElementCreateApplication(pid_t.max),
            lookup: WatcherFixture.textFieldLookup,
            frame: nil
        )
        probe.elementFrame = CGRect(x: 0, y: 0, width: 100, height: 20)
        let library = DraftLibrary(store: .inMemory)
        var monitor: InsertionTargetMonitor?
        let factory = InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        let controller = PanelControllerFactory.make(
            settings: settings,
            probe: probe,
            inserter: inserter,
            ownProcessIdentifier: Self.ownPid,
            library: library,
            animator: FakePanelFrameAnimator(),
            shaker: PanelShakerSpy(),
            beep: BeepSpy().beep,
            makeTargetMonitor: { model in
                let made = factory(model)
                monitor = made
                return made
            }
        )
        controller.targetOverride = { Self.safari }
        defer { controller.close() }
        controller.session.switchToInsert()
        controller.open()
        monitor?.refresh()
        controller.model.text = "secret"

        controller.commit(shouldSendAfterInsert: false)

        for _ in 0..<100 where inserter.calls.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await waitUntil(attempts: 100, interval: .milliseconds(10)) { controller.session.mode == .note }
        try await Task.sleep(for: .milliseconds(100))
        #expect(inserter.calls.count == 1)
        #expect(controller.session.mode == .note)
        #expect(!controller.model.isPresented)
        #expect(controller.model.text.isEmpty)
        #expect(library.history.isEmpty)
    }
}

private struct DefaultInspectorStub: FocusedTextInputInspecting {
    let state: FocusedTextInputState

    func focusedTextInputState(in target: InsertionTarget) -> FocusedTextInputState {
        state
    }
}
