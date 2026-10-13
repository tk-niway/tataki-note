import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DraftSessionTests {
    private static let ownProcessIdentifier: pid_t = 777
    private static let safari = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

    @MainActor
    private final class Fixture {
        let panel = PanelModel()
        let library: DraftLibrary
        let session: DraftSession

        init(store: DraftLibraryStore, target: InsertionTarget?, isKeyboardNavigationEnabled: @escaping () -> Bool = { false }) {
            library = DraftLibrary(store: store)
            session = DraftSession(
                panel: panel,
                library: library,
                ownProcessIdentifier: DraftSessionTests.ownProcessIdentifier,
                isKeyboardNavigationEnabled: isKeyboardNavigationEnabled
            )
            panel.present(target: target)
        }

        convenience init() {
            self.init(store: .inMemory, target: DraftSessionTests.safari)
        }

        convenience init(isKeyboardNavigationEnabled: @escaping () -> Bool) {
            self.init(store: .inMemory, target: DraftSessionTests.safari, isKeyboardNavigationEnabled: isKeyboardNavigationEnabled)
        }

        convenience init(store: DraftLibraryStore) {
            self.init(store: store, target: DraftSessionTests.safari)
        }

        convenience init(target: InsertionTarget?) {
            self.init(store: .inMemory, target: target)
        }

        func commit(isTrusted: Bool = true) -> CommitPlan {
            session.prepareCommit { panel.prepareCommit(isAccessibilityTrusted: isTrusted) }
        }

        func savedDraftID() -> UUID? {
            if case .savedDraft(let id) = session.document { return id }
            return nil
        }
    }

    // MARK: - 保存

    @Test("AC-11: ⌘S で今の文章が下書きに保存され、パネルの文章は残り、その下書きの表示になる")
    func saveCreatesDraftAndKeepsText() throws {
        let fixture = Fixture()
        fixture.panel.text = "hello\nworld"

        fixture.session.saveCurrent()

        let draft = try #require(fixture.library.drafts.first)
        #expect(fixture.library.drafts.count == 1)
        #expect(draft.text == "hello\nworld")
        #expect(fixture.panel.text == "hello\nworld")
        #expect(fixture.session.document == .savedDraft(draft.id))
        #expect(fixture.session.lastSaveEvent?.kind == .created(draft.id))
        #expect(fixture.session.lastSaveEvent?.origin == .saveCommand)
    }

    @Test("AC-11: 履歴から読み込んだ文章も ⌘S で下書きになる")
    func saveFromHistoryCreatesDraft() throws {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "from history", appName: "Safari", bundleIdentifier: nil)
        fixture.session.request(.history(fixture.library.history[0].id))

        fixture.session.saveCurrent()

        let draft = try #require(fixture.library.drafts.first)
        #expect(draft.text == "from history")
        #expect(fixture.session.document == .savedDraft(draft.id))
        #expect(fixture.library.history.count == 1)
    }

    @Test("AC-11: 本文が空のときの ⌘S は何もしない")
    func saveWithEmptyTextDoesNothing() {
        let fixture = Fixture()

        fixture.session.saveCurrent()

        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.session.lastSaveEvent == nil)
    }

    @Test("AC-11: 保存した下書きの表示中の ⌘S は下書きを増やさず、上書きの知らせになる")
    func saveOnSavedDraftOverwrites() throws {
        let fixture = Fixture()
        fixture.panel.text = "one"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())
        let firstEvent = try #require(fixture.session.lastSaveEvent)

        fixture.session.saveCurrent()

        #expect(fixture.library.drafts.count == 1)
        let secondEvent = try #require(fixture.session.lastSaveEvent)
        #expect(secondEvent.kind == .overwritten(id))
        #expect(secondEvent.origin == .saveCommand)
        #expect(secondEvent.sequence > firstEvent.sequence)
    }

    // MARK: - 自動の上書き

    @Test("AC-12: 保存した直後の下書きを書き換えると、⌘S を押さなくても保存してある本文が変わる")
    func editingSavedDraftOverwritesIt() throws {
        let fixture = Fixture()
        fixture.panel.text = "first"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())
        let eventBefore = fixture.session.lastSaveEvent

        fixture.panel.text = "first and more"

        #expect(fixture.library.draft(id: id)?.text == "first and more")
        #expect(fixture.library.drafts.count == 1)
        #expect(fixture.session.lastSaveEvent == eventBefore)
    }

    @Test("AC-12: 呼び戻した下書きを書き換えると、その下書きだけが変わる")
    func editingRecalledDraftOverwritesOnlyThatDraft() throws {
        let fixture = Fixture()
        fixture.panel.text = "alpha"
        fixture.session.saveCurrent()
        let alphaID = try #require(fixture.savedDraftID())
        fixture.session.request(.newScratch)
        fixture.panel.text = "beta"
        fixture.session.saveCurrent()
        let betaID = try #require(fixture.savedDraftID())

        fixture.session.request(.draft(alphaID))
        #expect(fixture.panel.text == "alpha")
        fixture.panel.text = "alpha edited"

        #expect(fixture.library.draft(id: alphaID)?.text == "alpha edited")
        #expect(fixture.library.draft(id: betaID)?.text == "beta")
        #expect(fixture.library.drafts.first?.id == alphaID)
    }

    @Test("AC-12: 書き換えは一覧にすぐ反映され、⌘S の書き出しで保存先に残る")
    func editingIsWrittenOnSave() throws {
        let directory = DraftLibraryTestDirectory()
        defer { directory.remove() }
        let store = DraftLibraryStore(directory: directory.dataDirectory)
        let fixture = Fixture(store: store)
        fixture.panel.text = "saved"
        fixture.session.saveCurrent()

        fixture.panel.text = "saved and edited"
        #expect(DraftLibrary(store: store).drafts.map(\.text) == ["saved"])

        fixture.session.saveCurrent()
        #expect(DraftLibrary(store: store).drafts.map(\.text) == ["saved and edited"])
    }

    // MARK: - 新しい書きかけ

    @Test("AC-13: ⌘N で、保存した下書きを表示中でも確認なしにパネルが空の新しい書きかけになる")
    func newScratchFromSavedDraftHasNoConfirmation() throws {
        let fixture = Fixture()
        fixture.panel.text = "keep me"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())
        let focusBefore = fixture.panel.focusRequest

        fixture.session.request(.newScratch)

        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.draft(id: id)?.text == "keep me")
        #expect(fixture.panel.focusRequest == focusBefore + 1)
    }

    @Test("AC-13: 本文が空の新しい書きかけでの ⌘N は何も起こらない")
    func newScratchFromEmptyScratchDoesNothing() {
        let fixture = Fixture()
        let focusBefore = fixture.panel.focusRequest

        fixture.session.request(.newScratch)

        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.focusRequest == focusBefore)
    }

    // MARK: - 保存していない文章の確認

    @Test("AC-14: 保存していない書きかけがあるまま ⌘N を押すと確認になり、文章は変わらない")
    func newScratchWithUnsavedTextAsksFirst() {
        let fixture = Fixture()
        fixture.panel.text = "unsaved"

        fixture.session.request(.newScratch)

        #expect(fixture.session.pendingSwitch == .newScratch)
        #expect(fixture.panel.text == "unsaved")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.drafts.isEmpty)
    }

    @Test("AC-14: 確認で「保存」を選ぶと、下書きに保存してから切り替わる")
    func resolveSaveSavesThenSwitches() throws {
        let fixture = Fixture()
        fixture.panel.text = "unsaved"
        fixture.session.request(.newScratch)

        fixture.session.resolvePendingSwitch(.save)

        let draft = try #require(fixture.library.drafts.first)
        #expect(fixture.library.drafts.count == 1)
        #expect(draft.text == "unsaved")
        #expect(fixture.session.lastSaveEvent?.kind == .created(draft.id))
        #expect(fixture.session.lastSaveEvent?.origin == .confirmation)
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "")
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-14: 確認で「保存しない」を選ぶと、文章を捨てて切り替わる")
    func resolveDiscardSwitchesWithoutSaving() throws {
        let fixture = Fixture()
        fixture.panel.text = "first"
        fixture.session.saveCurrent()
        let draftID = try #require(fixture.savedDraftID())
        fixture.session.request(.newScratch)
        fixture.panel.text = "unsaved"

        fixture.session.request(.draft(draftID))
        #expect(fixture.session.pendingSwitch == .draft(draftID))
        fixture.session.resolvePendingSwitch(.discard)

        #expect(fixture.library.drafts.count == 1)
        #expect(fixture.panel.text == "first")
        #expect(fixture.session.document == .savedDraft(draftID))
        #expect(fixture.session.pendingSwitch == nil)
    }

    @Test("AC-14: 確認で「キャンセル」を選ぶと、切り替えず文章もそのまま")
    func resolveCancelKeepsEverything() {
        let fixture = Fixture()
        fixture.panel.text = "unsaved"
        fixture.session.request(.newScratch)

        fixture.session.resolvePendingSwitch(.cancel)

        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "unsaved")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.drafts.isEmpty)
    }

    @Test("AC-14: 履歴から読み込んだ文章も保存していない文章なので、別の下書きの呼び出しは確認になる")
    func fromHistoryTextAsksBeforeSwitching() throws {
        let fixture = Fixture()
        fixture.panel.text = "draft"
        fixture.session.saveCurrent()
        let draftID = try #require(fixture.savedDraftID())
        fixture.library.recordInsertion(text: "history", appName: nil, bundleIdentifier: nil)
        fixture.session.request(.history(fixture.library.history[0].id))
        #expect(fixture.panel.text == "history")

        fixture.session.request(.draft(draftID))

        #expect(fixture.session.pendingSwitch == .draft(draftID))
        #expect(fixture.panel.text == "history")
    }

    @Test("AC-14: 本文が空・保存した下書きの表示中なら、確認なしで切り替わる")
    func switchingWithoutUnsavedTextHasNoConfirmation() throws {
        let fixture = Fixture()
        fixture.panel.text = "first"
        fixture.session.saveCurrent()
        let firstID = try #require(fixture.savedDraftID())
        fixture.session.request(.newScratch)
        fixture.panel.text = "second"
        fixture.session.saveCurrent()
        let secondID = try #require(fixture.savedDraftID())
        fixture.library.recordInsertion(text: "old", appName: nil, bundleIdentifier: nil)
        let historyID = fixture.library.history[0].id

        fixture.session.request(.draft(firstID))
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "first")

        fixture.session.request(.history(historyID))
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "old")
        #expect(fixture.session.document == .fromHistory(historyID))

        fixture.session.request(.newScratch)
        #expect(fixture.session.pendingSwitch == .newScratch)
        fixture.session.resolvePendingSwitch(.discard)
        fixture.session.request(.draft(secondID))
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "second")
    }

    @Test("AC-14: 切り替え先が消えているときは確認も切り替えもしない")
    func missingTargetDoesNothing() {
        let fixture = Fixture()
        fixture.panel.text = "unsaved"

        fixture.session.request(.draft(UUID()))
        fixture.session.request(.history(UUID()))

        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "unsaved")
        #expect(fixture.session.document == .scratch)
    }

    // MARK: - 確認で選んでいるボタン

    @Test("AC-6: 確認が出たとき、キーボードナビゲーションがオンなら選んでいるボタンは「保存」、オフなら無し")
    func confirmationFocusStartsOnSaveOnlyWhenKeyboardNavigationIsOn() {
        let on = Fixture(isKeyboardNavigationEnabled: { true })
        let off = Fixture(isKeyboardNavigationEnabled: { false })
        for fixture in [on, off] {
            fixture.panel.text = "typed"
            #expect(fixture.session.confirmationFocus == nil)
            fixture.session.request(.newScratch)
        }

        #expect(on.session.pendingSwitch == .newScratch)
        #expect(on.session.confirmationFocus == .save)
        #expect(off.session.pendingSwitch == .newScratch)
        #expect(off.session.confirmationFocus == nil)
    }

    @Test("AC-6: 確認中に別の切り替え先で確認を出し直すと、選んでいるボタンは「保存」に戻る")
    func reissuedConfirmationResetsFocusToSave() throws {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        let draft = try #require(fixture.library.addDraft(text: "saved"))
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)
        fixture.session.moveConfirmationFocus(by: 1)
        #expect(fixture.session.confirmationFocus == .discard)

        fixture.session.request(.draft(draft.id))

        #expect(fixture.session.pendingSwitch == .draft(draft.id))
        #expect(fixture.session.confirmationFocus == .save)
    }

    @Test("AC-6: 確認に答える・取り消すと、選んでいるボタンは無くなる", arguments: [UnsavedTextChoice.save, .discard, .cancel])
    func resolvingConfirmationClearsFocus(choice: UnsavedTextChoice) {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)
        #expect(fixture.session.confirmationFocus == .save)

        fixture.session.resolvePendingSwitch(choice)

        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.session.confirmationFocus == nil)
    }

    @Test("AC-6: キーボードナビゲーションの設定は確認が出た時点の値を使い、確認の途中で変わっても、その確認の間は変わらない")
    func keyboardNavigationIsReadWhenConfirmationAppears() {
        var isOn = true
        let fixture = Fixture(isKeyboardNavigationEnabled: { isOn })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)

        isOn = false

        #expect(fixture.session.confirmationFocus == .save)
        fixture.session.moveConfirmationFocus(by: 1)
        #expect(fixture.session.confirmationFocus == .discard)
    }

    @Test("AC-7: Tab の順に「保存」→「保存しない」→「キャンセル」→「保存」と移り、逆向きでは逆に回る")
    func confirmationFocusMovesAndWraps() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)

        var forward: [UnsavedTextChoice?] = []
        for _ in 0..<4 {
            fixture.session.moveConfirmationFocus(by: 1)
            forward.append(fixture.session.confirmationFocus)
        }
        #expect(forward == [.discard, .cancel, .save, .discard])

        var backward: [UnsavedTextChoice?] = []
        for _ in 0..<4 {
            fixture.session.moveConfirmationFocus(by: -1)
            backward.append(fixture.session.confirmationFocus)
        }
        #expect(backward == [.save, .cancel, .discard, .save])
        #expect(fixture.session.pendingSwitch == .newScratch)
        #expect(fixture.panel.text == "typed")
    }

    @Test("AC-7: キーボードナビゲーションがオフのとき、選んでいるボタンを動かしても何も選ばれない")
    func confirmationFocusDoesNotMoveWhenKeyboardNavigationIsOff() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { false })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)

        fixture.session.moveConfirmationFocus(by: 1)
        fixture.session.moveConfirmationFocus(by: -1)

        #expect(fixture.session.confirmationFocus == nil)
        #expect(fixture.session.pendingSwitch == .newScratch)
        #expect(fixture.panel.text == "typed")
    }

    @Test("AC-7: 確認が無いときに選んでいるボタンを動かしても何も起きない")
    func confirmationFocusDoesNotMoveWithoutConfirmation() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })

        fixture.session.moveConfirmationFocus(by: 1)

        #expect(fixture.session.confirmationFocus == nil)
        #expect(fixture.session.pendingSwitch == nil)
    }

    @Test("AC-8: 選んでいるボタンが「保存」なら、押すと保存して切り替わる")
    func resolveFocusedSaveSavesAndSwitches() throws {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)

        fixture.session.resolveFocusedConfirmation()

        let draft = try #require(fixture.library.drafts.first)
        #expect(draft.text == "typed")
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "")
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-8: 選んでいるボタンが「保存しない」なら、押すと捨てて切り替わる")
    func resolveFocusedDiscardDiscardsAndSwitches() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)
        fixture.session.moveConfirmationFocus(by: 1)
        #expect(fixture.session.confirmationFocus == .discard)

        fixture.session.resolveFocusedConfirmation()

        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "")
    }

    @Test("AC-8: 選んでいるボタンが「キャンセル」なら、押すと切り替えず文章もそのまま")
    func resolveFocusedCancelKeepsEverything() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { true })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)
        fixture.session.moveConfirmationFocus(by: -1)
        #expect(fixture.session.confirmationFocus == .cancel)

        fixture.session.resolveFocusedConfirmation()

        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.session.pendingSwitch == nil)
        #expect(fixture.panel.text == "typed")
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-8: キーボードナビゲーションがオフのとき、選んでいるボタンを押しても何もせず、確認も文章も変わらない")
    func resolveFocusedDoesNothingWhenKeyboardNavigationIsOff() {
        let fixture = Fixture(isKeyboardNavigationEnabled: { false })
        fixture.panel.text = "typed"
        fixture.session.request(.newScratch)

        fixture.session.resolveFocusedConfirmation()

        #expect(fixture.session.pendingSwitch == .newScratch)
        #expect(fixture.panel.text == "typed")
        #expect(fixture.library.drafts.isEmpty)
    }

    // MARK: - 挿入

    @Test("AC-15: 保存した下書きを挿入できたら、下書きは同じ本文のまま残り、パネルは空の新しい書きかけになる")
    func insertingSavedDraftKeepsItAndEmptiesPanel() throws {
        let fixture = Fixture()
        fixture.panel.text = "send this"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(plan == .insert(text: "send this", target: Self.safari))
        #expect(fixture.library.draft(id: id)?.text == "send this")
        #expect(fixture.panel.text == "")
        #expect(fixture.session.document == .scratch)
        #expect(!fixture.session.isNewDraftAvailable)
    }

    @Test("AC-15: 挿入のために本文が空になっても、保存した下書きは空で上書きされない")
    func commitDoesNotOverwriteDraftWithEmptyText() throws {
        let fixture = Fixture()
        fixture.panel.text = "send this"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        _ = fixture.commit()

        #expect(fixture.panel.text == "")
        #expect(fixture.library.draft(id: id)?.text == "send this")
    }

    @Test("AC-15: 挿入の後に書いた文章は、前の下書きを上書きしない")
    func typingAfterInsertionDoesNotTouchDraft() throws {
        let fixture = Fixture()
        fixture.panel.text = "send this"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())
        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        fixture.panel.present(target: Self.safari)
        fixture.panel.text = "next"

        #expect(fixture.library.draft(id: id)?.text == "send this")
        #expect(fixture.session.document == .scratch)
    }

    // MARK: - 履歴

    @Test("AC-16: 挿入に成功した文章は、挿入先のアプリ名と一緒に履歴に残る")
    func successfulInsertionIsRecorded() throws {
        let fixture = Fixture()
        fixture.panel.text = "history me"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        let entry = try #require(fixture.library.history.first)
        #expect(fixture.library.history.count == 1)
        #expect(entry.text == "history me")
        #expect(entry.appName == "Safari")
        #expect(entry.bundleIdentifier == "com.apple.Safari")
    }

    @Test("AC-16: 保存した下書きから挿入したときも履歴に残る")
    func insertionFromSavedDraftIsRecorded() {
        let fixture = Fixture()
        fixture.panel.text = "from draft"
        fixture.session.saveCurrent()

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.library.history.map(\.text) == ["from draft"])
        #expect(fixture.library.drafts.map(\.text) == ["from draft"])
    }

    @Test("AC-16: 挿入できなかったときは履歴に残らない")
    func failedInsertionIsNotRecorded() {
        let fixture = Fixture()
        fixture.panel.text = "will fail"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-16: 本文が空の確定は履歴に残らない")
    func emptyCommitIsNotRecorded() {
        let fixture = Fixture()

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(plan == .emptyText)
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-16: 権限が無い・挿入先が無いときは履歴に残らない")
    func commitWithoutPermissionOrTargetIsNotRecorded() {
        let denied = Fixture()
        denied.panel.text = "no permission"
        let deniedPlan = denied.commit(isTrusted: false)
        denied.session.finishCommit(deniedPlan, outcome: .notInserted)
        #expect(deniedPlan == .permissionDenied)
        #expect(denied.library.history.isEmpty)

        let noTarget = Fixture(target: nil)
        noTarget.panel.text = "no target"
        let noTargetPlan = noTarget.commit()
        noTarget.session.finishCommit(noTargetPlan, outcome: .notInserted)
        #expect(noTargetPlan == .noTarget)
        #expect(noTarget.library.history.isEmpty)
    }

    @Test("AC-16: チュートリアルの練習用のチャット(自分のアプリ)への挿入は履歴に残らない")
    func insertionIntoOwnAppIsNotRecorded() {
        let own = InsertionTarget(processIdentifier: Self.ownProcessIdentifier, bundleIdentifier: "jp.co.woube.TatakiNote", localizedName: "TatakiNote")
        let fixture = Fixture(target: own)
        fixture.panel.text = "practice"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.library.history.isEmpty)
        #expect(fixture.panel.text == "")
    }

    // MARK: - 挿入に失敗したとき

    @Test("AC-17: 保存した下書きから挿入して失敗し、文章がパネルに戻ったら、同じ下書きの表示に戻る")
    func failedInsertionRestoresSavedDraftDocument() throws {
        let fixture = Fixture()
        fixture.panel.text = "retry me"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.restoreDraft("retry me"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .savedDraft(id))
        fixture.panel.text = "retry me, edited"
        #expect(fixture.library.draft(id: id)?.text == "retry me, edited")
    }

    @Test("AC-17: 権限が無い・挿入先が無いときは、下書きの表示のまま変わらない")
    func noPermissionOrNoTargetKeepsSavedDraftDocument() throws {
        let denied = Fixture()
        denied.panel.text = "keep"
        denied.session.saveCurrent()
        let deniedID = try #require(denied.savedDraftID())
        let deniedPlan = denied.commit(isTrusted: false)
        denied.session.finishCommit(deniedPlan, outcome: .notInserted)
        #expect(denied.session.document == .savedDraft(deniedID))
        #expect(denied.panel.text == "keep")

        let noTarget = Fixture(target: nil)
        noTarget.panel.text = "keep"
        noTarget.session.saveCurrent()
        let noTargetID = try #require(noTarget.savedDraftID())
        let noTargetPlan = noTarget.commit()
        noTarget.session.finishCommit(noTargetPlan, outcome: .notInserted)
        #expect(noTarget.session.document == .savedDraft(noTargetID))
        #expect(noTarget.panel.text == "keep")
    }

    @Test("AC-17: 失敗の後に文章を戻せなかった(パネルに別の文章がある)ときは、保存していない書きかけのまま")
    func failedInsertionWithNewTextStaysScratch() throws {
        let fixture = Fixture()
        fixture.panel.text = "old"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        fixture.panel.text = "new text"
        #expect(!fixture.panel.restoreDraft("old"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.draft(id: id)?.text == "old")
    }

    @Test("AC-17: 失敗の間に下書きが消えたときは、保存していない書きかけのまま")
    func failedInsertionAfterDraftWasDeletedStaysScratch() throws {
        let fixture = Fixture()
        fixture.panel.text = "gone"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        fixture.session.deleteDraft(id: id)
        #expect(fixture.panel.restoreDraft("gone"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.drafts.isEmpty)
    }

    // MARK: - 削除

    @Test("AC-18: パネルに出している下書きを削除すると、本文はパネルに残り、保存していない書きかけになる")
    func deletingShownDraftKeepsTextAsScratch() throws {
        let fixture = Fixture()
        fixture.panel.text = "shown"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        fixture.session.deleteDraft(id: id)

        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.panel.text == "shown")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.session.hasUnsavedText)
        fixture.panel.text = "shown, edited"
        #expect(fixture.library.drafts.isEmpty)
    }

    @Test("AC-18: 表示していない下書きを削除しても、パネルの文章と扱いは変わらない")
    func deletingOtherDraftLeavesDocument() throws {
        let fixture = Fixture()
        fixture.panel.text = "other"
        fixture.session.saveCurrent()
        let otherID = try #require(fixture.savedDraftID())
        fixture.session.request(.newScratch)
        fixture.panel.text = "shown"
        fixture.session.saveCurrent()
        let shownID = try #require(fixture.savedDraftID())

        fixture.session.deleteDraft(id: otherID)

        #expect(fixture.library.drafts.map(\.id) == [shownID])
        #expect(fixture.session.document == .savedDraft(shownID))
        #expect(fixture.panel.text == "shown")
    }

    // MARK: - 履歴の読み込み

    @Test("AC-19: 履歴を選ぶと、その文章の写しがパネルに入り、保存していない文章の扱いになる")
    func loadingHistoryCopiesTextIntoPanel() {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: "Notes", bundleIdentifier: nil)
        let id = fixture.library.history[0].id

        fixture.session.request(.history(id))

        #expect(fixture.panel.text == "past text")
        #expect(fixture.session.document == .fromHistory(id))
        #expect(fixture.session.hasUnsavedText)
    }

    @Test("AC-19: 読み込んだ文章をパネルで書き換えても履歴は変わらず、⌘S で下書きにできる")
    func editingLoadedHistoryDoesNotChangeHistory() throws {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: nil, bundleIdentifier: nil)
        let entry = fixture.library.history[0]
        fixture.session.request(.history(entry.id))

        fixture.panel.text = "past text edited"

        #expect(fixture.library.history == [entry])
        #expect(fixture.library.drafts.isEmpty)
        fixture.session.saveCurrent()
        let draft = try #require(fixture.library.drafts.first)
        #expect(draft.text == "past text edited")
        #expect(fixture.session.document == .savedDraft(draft.id))
        #expect(fixture.library.history == [entry])
    }

    @Test("AC-19: 読み込んだ文章を挿入できたら、パネルは空の新しい書きかけになり、新規作成のアイコンは押せない")
    func insertingLoadedHistoryEmptiesPanel() {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: nil, bundleIdentifier: nil)
        fixture.session.request(.history(fixture.library.history[0].id))

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.panel.text == "")
        #expect(fixture.session.document == .scratch)
        #expect(!fixture.session.isNewDraftAvailable)
        #expect(fixture.library.history.count == 2)
    }

    @Test("AC-19: 読み込んだ文章の挿入に失敗して文章がパネルに戻ったら、また履歴から読み込んだ文章の扱いに戻る")
    func failedInsertionRestoresFromHistoryDocument() {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: nil, bundleIdentifier: nil)
        let id = fixture.library.history[0].id
        fixture.session.request(.history(id))

        let plan = fixture.commit()
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.restoreDraft("past text"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .fromHistory(id))
        #expect(fixture.library.history.count == 1)
    }

    @Test("AC-19: 履歴の1件を消しても、読み込んだ文章の扱いは変わらない")
    func deletingHistoryEntryKeepsLoadedDocument() {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: nil, bundleIdentifier: nil)
        let id = fixture.library.history[0].id
        fixture.session.request(.history(id))

        fixture.session.deleteHistoryEntry(id: id)

        #expect(fixture.library.history.isEmpty)
        #expect(fixture.session.document == .fromHistory(id))
        #expect(fixture.panel.text == "past text")
    }

    // MARK: - 書きかけ

    @Test("AC-20: 保存していない書きかけは、パネルを閉じて開き直しても残る")
    func scratchSurvivesCloseAndReopen() {
        let fixture = Fixture()
        fixture.panel.text = "work in progress"

        fixture.panel.dismiss()
        fixture.panel.present(target: Self.safari)

        #expect(fixture.panel.text == "work in progress")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.drafts.isEmpty)
    }

    @Test("AC-20: 保存していない書きかけは、挿入できたら空になり、下書きも履歴以外は増えない")
    func scratchIsEmptiedByInsertion() {
        let fixture = Fixture()
        fixture.panel.text = "send"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.panel.text == "")
        #expect(fixture.library.drafts.isEmpty)
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-20: 挿入に失敗した書きかけはパネルに戻り、書きかけのまま")
    func failedScratchStaysScratch() {
        let fixture = Fixture()
        fixture.panel.text = "send"

        let plan = fixture.commit()
        #expect(fixture.panel.restoreDraft("send"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.panel.text == "send")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.drafts.isEmpty)
    }

    // MARK: - タイトルバーのアイコン

    @Test("AC-28: 保存のアイコンは本文が空なら押せない")
    func saveIsUnavailableForEmptyText() {
        let fixture = Fixture()
        #expect(!fixture.session.isSaveAvailable)

        fixture.panel.text = "x"
        #expect(fixture.session.isSaveAvailable)

        fixture.panel.text = ""
        #expect(!fixture.session.isSaveAvailable)
    }

    @Test("AC-28: 新規作成のアイコンは、本文が空の新しい書きかけを表示しているときだけ押せない")
    func newDraftIsUnavailableOnlyForEmptyScratch() throws {
        let fixture = Fixture()
        #expect(!fixture.session.isNewDraftAvailable)

        fixture.panel.text = "x"
        #expect(fixture.session.isNewDraftAvailable)

        fixture.session.saveCurrent()
        #expect(fixture.session.isNewDraftAvailable)

        fixture.panel.text = ""
        #expect(fixture.session.isNewDraftAvailable)

        fixture.session.request(.newScratch)
        #expect(!fixture.session.isNewDraftAvailable)

        fixture.library.recordInsertion(text: "past", appName: nil, bundleIdentifier: nil)
        fixture.session.request(.history(fixture.library.history[0].id))
        #expect(fixture.session.isNewDraftAvailable)
    }
}
