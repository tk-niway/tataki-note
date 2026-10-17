import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class ModeSetting {
    var value: DraftMode

    init(_ value: DraftMode) {
        self.value = value
    }
}

@MainActor
private struct SessionFixture {
    static let safari = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

    let panel = PanelModel()
    let library = DraftLibrary(store: .inMemory)
    let setting: ModeSetting
    let session: DraftSession

    init(setting: DraftMode = .insert, target: InsertionTarget? = nil, hasTarget: Bool = true) {
        let setting = ModeSetting(setting)
        self.setting = setting
        self.session = DraftSession(
            panel: panel,
            library: library,
            ownProcessIdentifier: 777,
            newDraftMode: { setting.value }
        )
        panel.present(target: hasTarget ? (target ?? Self.safari) : nil)
    }

    func commit(isTrusted: Bool = true) -> CommitPlan {
        session.prepareCommit { panel.prepareCommit(isAccessibilityTrusted: isTrusted) }
    }
}

@MainActor
struct DraftModeTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: DraftModeTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")

    @MainActor
    private struct Fixture {
        let controller: PanelController
        let settings: AppSettings
        let shaker: PanelShakerSpy
        let inserter: InserterStub
        let permission: PermissionStub

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
    }

    private func withFixture(
        newDraftMode: DraftMode = .insert,
        insertionResult: InsertionResult = .inserted,
        isTrusted: Bool = true,
        hasTarget: Bool = true,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.newDraftMode = newDraftMode
        settings.panelScreen = .main
        settings.animationMode = .off
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let shaker = PanelShakerSpy()
        let inserter = InserterStub(result: insertionResult)
        let permission = PermissionStub(isTrusted: isTrusted)
        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: permission,
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: DraftLibrary(store: .inMemory),
            animator: FakePanelFrameAnimator(),
            shaker: shaker,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        if hasTarget {
            controller.targetOverride = { own }
        } else {
            controller.isTargetLookupDisabled = true
        }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, settings: settings, shaker: shaker, inserter: inserter, permission: permission))
    }

    private func waitForInsertion(_ inserter: InserterStub) async {
        for _ in 0..<100 where inserter.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private var newDraftKey: PanelKeyInput {
        PanelKeyInput(keyCode: 45, modifiers: [.command], hasMarkedText: false, characters: "n")
    }

    // MARK: - 起動したとき

    @Test("AC-1: 作った直後の書きかけのモードは、新しい書きかけのモードの値になる", arguments: DraftMode.allCases)
    func initialModeFollowsSetting(setting: DraftMode) {
        let fixture = SessionFixture(setting: setting)

        #expect(fixture.session.mode == setting)
    }

    @Test("AC-1: 新しい書きかけのモードを渡さずに作ると、インサートで始まる")
    func initialModeDefaultsToInsert() {
        let panel = PanelModel()
        let session = DraftSession(panel: panel, library: DraftLibrary(store: .inMemory))

        #expect(session.mode == .insert)
    }

    @Test("AC-1: パネルの書きかけは、保存した設定のモードで始まる", arguments: DraftMode.allCases)
    func panelSessionStartsWithSavedSetting(setting: DraftMode) async throws {
        try await withFixture(newDraftMode: setting) { fixture in
            #expect(fixture.session.mode == setting)
        }
    }

    // MARK: - ⌘N・新規作成のアイコン

    @Test("AC-3: 新しい書きかけにすると、モードが新しい書きかけのモードの値に戻る(本文が空のままでも)", arguments: DraftMode.allCases)
    func newScratchResetsModeToSetting(setting: DraftMode) {
        let fixture = SessionFixture(setting: setting)
        fixture.session.toggleMode()
        #expect(fixture.session.mode == setting.toggled)

        fixture.session.request(.newScratch)

        #expect(fixture.session.mode == setting)
    }

    @Test("AC-3: 本文がある書きかけからでも、新しい書きかけにするとモードが戻り、本文は空になる")
    func newScratchResetsModeFromScratchWithText() {
        let fixture = SessionFixture(setting: .insert)
        fixture.panel.text = "draft"
        fixture.session.toggleMode()

        fixture.session.request(.newScratch)

        #expect(fixture.session.mode == .insert)
        #expect(fixture.panel.text == "")
    }

    @Test("AC-3: すでに新しい書きかけのモードの値なら、新しい書きかけにしても変わらない", arguments: DraftMode.allCases)
    func newScratchKeepsModeWhenAlreadySetting(setting: DraftMode) {
        let fixture = SessionFixture(setting: setting)

        fixture.session.request(.newScratch)
        fixture.session.request(.newScratch)

        #expect(fixture.session.mode == setting)
    }

    @Test("AC-3: ⌘N で新しい書きかけにすると、本文が空のままでもモードが設定の値に戻る")
    func commandNResetsMode() async throws {
        try await withFixture(newDraftMode: .insert) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()
            #expect(fixture.session.mode == .note)

            #expect(fixture.controller.handleKey(newDraftKey))

            #expect(fixture.session.mode == .insert)
        }
    }

    @Test("AC-3: 新規作成のアイコンで新しい書きかけにすると、本文が空のままでもモードが設定の値に戻る")
    func newDraftButtonResetsMode() async throws {
        try await withFixture(newDraftMode: .note) { fixture in
            fixture.controller.open()
            fixture.session.switchToInsert()
            #expect(fixture.session.mode == .insert)

            fixture.controller.newDraftFromButton()

            #expect(fixture.session.mode == .note)
        }
    }

    // MARK: - 挿入できたとき

    @Test("AC-5: 挿入できると、次の書きかけのモードは新しい書きかけのモードの値になる", arguments: DraftMode.allCases)
    func insertionResetsModeToSetting(setting: DraftMode) {
        let fixture = SessionFixture(setting: setting)
        fixture.session.toggleMode()
        #expect(fixture.session.mode == setting.toggled)
        fixture.panel.text = "send"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.session.mode == setting)
    }

    @Test("AC-5: 自分のアプリ(練習用のチャット)に挿入できたときも、モードが戻る")
    func insertionIntoOwnAppResetsMode() {
        let fixture = SessionFixture(setting: .note, target: InsertionTarget(processIdentifier: 777, bundleIdentifier: nil, localizedName: "TatakiNote"))
        fixture.session.switchToInsert()
        fixture.panel.text = "practice"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.session.mode == .note)
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-5: パネルで確定+挿入・確定+送信で挿入できると、次の書きかけが設定のモードで始まる", arguments: [false, true])
    func panelInsertionResetsMode(shouldSend: Bool) async throws {
        try await withFixture(newDraftMode: .note) { fixture in
            fixture.session.switchToInsert()
            fixture.controller.open()
            fixture.model.text = "hello"

            fixture.controller.commit(shouldSendAfterInsert: shouldSend)

            await waitForInsertion(fixture.inserter)
            try await waitUntil(attempts: 100, interval: .milliseconds(10)) { fixture.session.mode == .note }
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
            #expect(fixture.session.mode == .note)
        }
    }

    // MARK: - 戻さないとき

    @Test("AC-6: サイドバーから下書き・履歴を開いても、モードは変わらない")
    func openingDraftOrHistoryKeepsMode() throws {
        let fixture = SessionFixture(setting: .insert)
        let draft = try #require(fixture.library.addDraft(text: "saved"))
        fixture.library.recordInsertion(text: "past", appName: nil, bundleIdentifier: nil)
        let entry = try #require(fixture.library.history.first)
        fixture.session.toggleMode()

        fixture.session.request(.draft(draft.id))
        #expect(fixture.session.mode == .note)

        fixture.session.request(.history(entry.id))
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-6: 表示中の下書きを消しても、モードは変わらない")
    func deletingShownDraftKeepsMode() throws {
        let fixture = SessionFixture(setting: .insert)
        fixture.panel.text = "keep"
        fixture.session.saveCurrent()
        guard case .savedDraft(let id) = fixture.session.document else {
            Issue.record("下書きの表示になっていない")
            return
        }
        fixture.session.toggleMode()

        fixture.session.deleteDraft(id: id)

        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.text == "keep")
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-6: 挿入できずに文章がパネルに戻っても、モードは変わらない")
    func notInsertedKeepsMode() {
        let fixture = SessionFixture(setting: .insert)
        fixture.panel.text = "send"
        fixture.session.toggleMode()

        let plan = fixture.commit()
        #expect(fixture.panel.restoreDraft("send"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.mode == .note)
    }

    @Test("AC-6: アクセシビリティの許可が無いときの確定でも、モードは変わらない")
    func permissionDeniedKeepsMode() {
        let fixture = SessionFixture(setting: .insert)
        fixture.panel.text = "send"
        fixture.session.toggleMode()

        let plan = fixture.commit(isTrusted: false)
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(plan == .permissionDenied)
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-6: 本文が空・挿入先なしで確定できないときも、モードは変わらない")
    func rejectedCommitKeepsMode() {
        let empty = SessionFixture(setting: .insert)
        empty.session.toggleMode()
        let emptyPlan = empty.commit()
        empty.session.finishCommit(emptyPlan, outcome: .notInserted)
        #expect(emptyPlan == .emptyText)
        #expect(empty.session.mode == .note)

        let noTarget = SessionFixture(setting: .insert, hasTarget: false)
        noTarget.panel.text = "send"
        noTarget.session.toggleMode()
        let noTargetPlan = noTarget.commit()
        noTarget.session.finishCommit(noTargetPlan, outcome: .notInserted)
        #expect(noTargetPlan == .noTarget)
        #expect(noTarget.session.mode == .note)
    }

    @Test("AC-6: パネルを閉じて開き直しても、モードは変わらない")
    func reopeningKeepsMode() async throws {
        try await withFixture(newDraftMode: .insert) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()

            fixture.controller.close()
            fixture.controller.open()

            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-6: パネルで挿入に失敗して文章が戻っても、モードは変わらない")
    func panelNotInsertedKeepsMode() async throws {
        try await withFixture(newDraftMode: .insert, insertionResult: .noTextInput) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()
            fixture.model.text = "hello"

            fixture.controller.commit()

            await waitForInsertion(fixture.inserter)
            await settle()
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-6: パネルで許可が無くて確定できなくても、モードは変わらない")
    func panelPermissionDeniedKeepsMode() async throws {
        try await withFixture(newDraftMode: .insert, isTrusted: false) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()
            fixture.model.text = "hello"

            fixture.controller.commit()

            await settle()
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-6: パネルで本文が空のまま確定しても、モードは変わらない")
    func panelEmptyCommitKeepsMode() async throws {
        try await withFixture(newDraftMode: .insert) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()

            fixture.controller.commit()

            #expect(fixture.shaker.shakeCount == 1)
            #expect(fixture.session.mode == .note)
        }
    }

    @Test("AC-6: パネルで挿入先が無くて確定できなくても、モードは変わらない")
    func panelNoTargetKeepsMode() async throws {
        try await withFixture(newDraftMode: .insert, hasTarget: false) { fixture in
            fixture.controller.open()
            fixture.session.toggleMode()
            fixture.model.text = "hello"

            fixture.controller.commit()

            await settle()
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.session.mode == .note)
        }
    }

    // MARK: - 設定を変えたとき

    @Test("AC-7: 新しい書きかけのモードを変えても今の書きかけのモードは変わらず、新しい書きかけにしたときから効く")
    func settingChangeAppliesFromNextNewDraft() {
        let fixture = SessionFixture(setting: .insert)

        fixture.setting.value = .note
        #expect(fixture.session.mode == .insert)

        fixture.session.request(.newScratch)
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-7: 設定を変えても今のモードは変わらず、挿入できたあとから効く")
    func settingChangeAppliesAfterInsertion() {
        let fixture = SessionFixture(setting: .insert)
        fixture.panel.text = "send"

        fixture.setting.value = .note
        #expect(fixture.session.mode == .insert)

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)
        #expect(fixture.session.mode == .note)
    }

    @Test("AC-7: パネルの設定の値を変えても今の書きかけのモードは変わらず、⌘N のあとから効く", arguments: DraftMode.allCases)
    func panelSettingChangeAppliesFromNextNewDraft(setting: DraftMode) async throws {
        try await withFixture(newDraftMode: setting.toggled) { fixture in
            #expect(fixture.session.mode == setting.toggled)

            fixture.settings.newDraftMode = setting
            #expect(fixture.session.mode == setting.toggled)

            #expect(fixture.controller.handleKey(newDraftKey))
            #expect(fixture.session.mode == setting)
        }
    }
}
