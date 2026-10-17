import AppKit
import Foundation
import Testing
@testable import TatakiNote

enum ScratchArchiveCloseWay: CaseIterable, Sendable {
    case escape
    case closeImmediately
    case hideKey
    case commitWithoutPermission
}

enum ScratchArchiveDocumentState: CaseIterable, Sendable {
    case savedDraft
    case fromHistory
    case editedFromHistory
    case scratch
    case emptyScratch
}

enum ScratchArchiveNonArchivedCase: CaseIterable, Sendable {
    case blankScratch
    case shownSavedDraft
    case unmodifiedHistory
}

enum ScratchArchiveLeaveWay: CaseIterable, Sendable {
    case openDraft
    case newScratch
    case terminate
}

@MainActor
struct ScratchArchiveTests {
    private static let ownProcessIdentifier: pid_t = 777
    private static let safari = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

    @MainActor
    private final class SessionFixture {
        let panel = PanelModel()
        let library: DraftLibrary
        let session: DraftSession

        init(historyLimit: Int = HistoryLimit.defaultValue) {
            library = DraftLibrary(store: .inMemory, historyLimit: historyLimit)
            session = DraftSession(
                panel: panel,
                library: library,
                ownProcessIdentifier: ScratchArchiveTests.ownProcessIdentifier
            )
            panel.present(target: ScratchArchiveTests.safari)
        }

        func addDraft(_ text: String) throws -> SavedDraft {
            try #require(library.addDraft(text: text))
        }

        func commit() -> CommitPlan {
            session.prepareCommit { panel.prepareCommit(isAccessibilityTrusted: true) }
        }

        func leave(_ way: ScratchArchiveLeaveWay, to draft: SavedDraft) {
            switch way {
            case .openDraft: session.request(.draft(draft.id))
            case .newScratch: session.request(.newScratch)
            case .terminate: session.prepareForTermination()
            }
        }
    }

    @MainActor
    private final class ControllerFixture {
        let directory: URL
        let defaultsName: String
        let library: DraftLibrary
        let animator = FakePanelFrameAnimator()
        let controller: PanelController

        init(isTrusted: Bool = true, isAnimationEnabled: Bool = false) throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let defaultsName = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.panelScreen = .main
            settings.panelDefaultWidth = 600
            settings.panelDefaultHeight = 400
            settings.animationMode = isAnimationEnabled ? .on : .off
            let library = DraftLibrary(store: DraftLibraryStore(directory: directory))
            let probe = FocusedElementProbeStub()
            self.directory = directory
            self.defaultsName = defaultsName
            self.library = library
            self.controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                inserter: InserterStub(result: .inserted),
                permission: PermissionStub(isTrusted: isTrusted),
                fieldProbe: probe,
                library: library,
                animator: animator,
                beep: {},
                hideApplication: {},
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            )
            controller.targetOverride = { ScratchArchiveTests.textEdit }
        }

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }

        func reloadedLibrary() -> DraftLibrary {
            DraftLibrary(store: DraftLibraryStore(directory: directory))
        }

        func cleanup() {
            controller.close()
            controller.panel.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }
    }

    private static func commandN() -> PanelKeyInput {
        PanelKeyInput(keyCode: 45, modifiers: [.command], hasMarkedText: false, characters: "n")
    }

    // MARK: - 切り替えで移す

    @Test("AC-6: 書きかけがあるとき ⌘N で新しい書きかけにすると、前の書きかけが挿入していない履歴の先頭に入り、パネルは空になる")
    func commandNArchivesScratch() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.library.recordInsertion(text: "inserted", appName: "Notes", bundleIdentifier: nil)
        fixture.model.text = "abc"

        #expect(fixture.controller.handleKey(Self.commandN()))

        let entry = try #require(fixture.library.history.first)
        #expect(entry.text == "abc")
        #expect(!entry.isInserted)
        #expect(fixture.library.history.count == 2)
        #expect(fixture.model.text.isEmpty)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.session.archivedScratchCount == 1)
    }

    @Test("AC-6: 書きかけがあるとき新規作成のアイコンで新しい書きかけにすると、前の書きかけが挿入していない履歴の先頭に入り、パネルは空になる")
    func newDraftButtonArchivesScratch() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "abc"

        fixture.controller.newDraftFromButton()

        let entry = try #require(fixture.library.history.first)
        #expect(entry.text == "abc")
        #expect(!entry.isInserted)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.model.text.isEmpty)
        #expect(fixture.session.archivedScratchCount == 1)
    }

    @Test("AC-6: 移した書きかけは保存先にも書き出され、読み直しても挿入していない履歴として残る")
    func archivedScratchIsPersisted() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "abc"

        fixture.controller.newDraftFromButton()

        let reloaded = try #require(fixture.reloadedLibrary().history.first)
        #expect(reloaded.text == "abc")
        #expect(!reloaded.isInserted)
    }

    @Test("AC-7: 表示中の下書きを消しても、その時点では履歴に入らず、別の下書きを開くと挿入していない履歴に入る")
    func deletingShownDraftArchivesOnNextSwitch() throws {
        let fixture = SessionFixture()
        let shown = try fixture.addDraft("shown")
        let other = try fixture.addDraft("other")
        fixture.session.request(.draft(shown.id))

        fixture.session.deleteDraft(id: shown.id)

        #expect(fixture.panel.text == "shown")
        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.session.archivedScratchCount == 0)

        fixture.session.request(.draft(other.id))

        let entry = try #require(fixture.library.history.first)
        #expect(entry.text == "shown")
        #expect(!entry.isInserted)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.session.archivedScratchCount == 1)
    }

    @Test("AC-8: 空白だけの書きかけ・表示中の下書き・書き換えていない履歴は、別の文章を開いても ⌘N でも履歴に足さない",
          arguments: ScratchArchiveNonArchivedCase.allCases, [false, true])
    func nonArchivedCasesAddNothing(_ scenario: ScratchArchiveNonArchivedCase, switchesToNewScratch: Bool) throws {
        let fixture = SessionFixture()
        let other = try fixture.addDraft("other")
        fixture.library.recordInsertion(text: "past", appName: "Notes", bundleIdentifier: nil)
        let historyBefore = fixture.library.history
        switch scenario {
        case .blankScratch:
            fixture.panel.text = " \n\t "
        case .shownSavedDraft:
            let shown = try fixture.addDraft("shown")
            fixture.session.request(.draft(shown.id))
            fixture.panel.text = "shown, edited"
        case .unmodifiedHistory:
            fixture.session.request(.history(historyBefore[0].id))
        }

        if switchesToNewScratch {
            fixture.session.request(.newScratch)
        } else {
            fixture.session.request(.draft(other.id))
        }

        #expect(fixture.library.history == historyBefore)
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-9: 履歴を選ぶと文章がパネルに出るが履歴は変わらず、書き換えると書きかけになり、切り替えで新しい履歴として入る")
    func editedHistoryCopyBecomesNewEntry() throws {
        let fixture = SessionFixture()
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        let original = try #require(fixture.library.history.first)

        fixture.session.request(.history(original.id))

        #expect(fixture.panel.text == "orig")
        #expect(fixture.session.document == .fromHistory(original.id))
        #expect(fixture.library.history == [original])

        fixture.panel.text = "orig, edited"

        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.history == [original])

        fixture.session.request(.newScratch)

        #expect(fixture.library.history.count == 2)
        let added = try #require(fixture.library.history.first)
        #expect(added.text == "orig, edited")
        #expect(!added.isInserted)
        #expect(fixture.library.history[1] == original)
        #expect(fixture.library.history[1].text == "orig")
        #expect(fixture.session.archivedScratchCount == 1)
    }

    // MARK: - 閉じる

    @Test("AC-10: パネルを閉じても、書きかけは履歴に移らずパネルに残る", arguments: ScratchArchiveCloseWay.allCases)
    func closingKeepsScratchOutOfHistory(_ way: ScratchArchiveCloseWay) throws {
        let fixture = try ControllerFixture(
            isTrusted: way != .commitWithoutPermission,
            isAnimationEnabled: way == .hideKey
        )
        defer { fixture.cleanup() }
        fixture.controller.open()
        fixture.model.text = "abc"

        switch way {
        case .escape:
            #expect(fixture.controller.handleKey(PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false)))
        case .closeImmediately:
            fixture.controller.closeImmediately()
        case .hideKey:
            #expect(fixture.controller.handleHideKey())
        case .commitWithoutPermission:
            fixture.controller.commit()
        }

        #expect(!fixture.model.isPresented)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.session.archivedScratchCount == 0)
        #expect(fixture.session.document == .scratch)
        #expect(fixture.model.text == "abc")
    }

    @Test("AC-10: 閉じるボタンでも、書きかけは履歴に移らずパネルに残る")
    func closeButtonKeepsScratchOutOfHistory() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.controller.open()
        fixture.model.text = "abc"

        fixture.controller.closeFromButton()

        #expect(!fixture.model.isPresented)
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.model.text == "abc")
    }

    @Test("AC-11: 閉じた後に開き直すと、閉じる直前の扱いと文章のまま出ている", arguments: ScratchArchiveDocumentState.allCases)
    func reopeningKeepsDocument(_ state: ScratchArchiveDocumentState) throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        let draft = try #require(fixture.library.addDraft(text: "draft body"))
        fixture.library.recordInsertion(text: "past body", appName: "Notes", bundleIdentifier: nil)
        let entry = try #require(fixture.library.history.first)
        fixture.controller.open()
        let expectedDocument: PanelDocument
        let expectedText: String
        switch state {
        case .savedDraft:
            fixture.session.request(.draft(draft.id))
            expectedDocument = .savedDraft(draft.id)
            expectedText = "draft body"
        case .fromHistory:
            fixture.session.request(.history(entry.id))
            expectedDocument = .fromHistory(entry.id)
            expectedText = "past body"
        case .editedFromHistory:
            fixture.session.request(.history(entry.id))
            fixture.model.text = "past body, edited"
            expectedDocument = .scratch
            expectedText = "past body, edited"
        case .scratch:
            fixture.model.text = "abc"
            expectedDocument = .scratch
            expectedText = "abc"
        case .emptyScratch:
            expectedDocument = .scratch
            expectedText = ""
        }
        let historyBefore = fixture.library.history

        fixture.controller.close()
        fixture.controller.open()

        #expect(fixture.model.isPresented)
        #expect(fixture.session.document == expectedDocument)
        #expect(fixture.model.text == expectedText)
        #expect(fixture.library.history == historyBefore)
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-11: 閉じて開き直した後の ⌘N で、そこで初めて書きかけが履歴に入る")
    func scratchIsArchivedOnlyAfterReopenedAndSwitched() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.controller.open()
        fixture.model.text = "abc"
        fixture.controller.close()
        fixture.controller.open()
        #expect(fixture.library.history.isEmpty)

        #expect(fixture.controller.handleKey(Self.commandN()))

        #expect(fixture.library.history.map(\.text) == ["abc"])
    }

    // MARK: - 元と同じ本文に戻したもの

    @Test("AC-12: 履歴の写しを書き換えて元と同じ本文に戻すと、別の文章を開く・⌘N・終了でも履歴に残さない",
          arguments: ScratchArchiveLeaveWay.allCases)
    func restoredHistoryCopyIsNotArchived(_ way: ScratchArchiveLeaveWay) throws {
        let fixture = SessionFixture()
        let other = try fixture.addDraft("other")
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        let original = try #require(fixture.library.history.first)
        fixture.session.request(.history(original.id))
        fixture.panel.text = "orig!"
        fixture.panel.text = "orig"

        fixture.leave(way, to: other)

        #expect(fixture.library.history == [original])
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-12: 履歴の写しを表示中に挿入できず戻った後も、元と同じ本文に戻せば履歴に残さない")
    func failedInsertionOfHistoryCopyKeepsSource() throws {
        let fixture = SessionFixture()
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        let original = try #require(fixture.library.history.first)
        fixture.session.request(.history(original.id))

        let plan = fixture.commit()
        #expect(fixture.panel.restoreDraft("orig"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .fromHistory(original.id))
        fixture.panel.text = "orig!"
        fixture.panel.text = "orig"
        fixture.session.request(.newScratch)

        #expect(fixture.library.history == [original])
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-12: 書き換えた写しを挿入できず戻った後も、元と同じ本文に戻せば履歴に残さない")
    func failedInsertionOfEditedCopyKeepsSource() throws {
        let fixture = SessionFixture()
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        let original = try #require(fixture.library.history.first)
        fixture.session.request(.history(original.id))
        fixture.panel.text = "orig!"

        let plan = fixture.commit()
        #expect(fixture.panel.restoreDraft("orig!"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .scratch)
        fixture.panel.text = "orig"
        fixture.session.request(.newScratch)

        #expect(fixture.library.history == [original])
        #expect(fixture.session.archivedScratchCount == 0)
    }

    // MARK: - 挿入

    @Test("AC-13: 書きかけを挿入できたら挿入した履歴に1件だけ入り、挿入していない履歴も下書きも増えない")
    func insertedScratchIsOnlyInsertedHistory() throws {
        let fixture = SessionFixture()
        fixture.panel.text = "abc"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.library.history.count == 1)
        let entry = try #require(fixture.library.history.first)
        #expect(entry.text == "abc")
        #expect(entry.isInserted)
        #expect(fixture.library.drafts.isEmpty)
        fixture.session.request(.newScratch)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-13: 履歴の写しを書き換えたものを挿入できたら、挿入した履歴に1件だけ増え、挿入していない履歴は増えない")
    func insertedEditedCopyIsOnlyInsertedHistory() throws {
        let fixture = SessionFixture()
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        fixture.session.request(.history(fixture.library.history[0].id))
        fixture.panel.text = "orig, edited"

        let plan = fixture.commit()
        fixture.session.finishCommit(plan, outcome: .inserted)

        #expect(fixture.library.history.count == 2)
        #expect(fixture.library.history.filter { !$0.isInserted }.isEmpty)
        #expect(fixture.library.history.first?.text == "orig, edited")
        #expect(fixture.library.drafts.isEmpty)
        fixture.session.request(.newScratch)
        #expect(fixture.library.history.count == 2)
    }

    @Test("AC-13: 挿入できずに文章がパネルに戻ったら書きかけのままで、別の文章を開くと挿入していない履歴に入る")
    func failedInsertionKeepsScratch() throws {
        let fixture = SessionFixture()
        let other = try fixture.addDraft("other")
        fixture.panel.text = "abc"

        let plan = fixture.commit()
        #expect(fixture.library.history.isEmpty)
        #expect(fixture.panel.restoreDraft("abc"))
        fixture.session.finishCommit(plan, outcome: .notInserted)

        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.history.isEmpty)
        fixture.session.request(.draft(other.id))
        let entry = try #require(fixture.library.history.first)
        #expect(entry.text == "abc")
        #expect(!entry.isInserted)
        #expect(fixture.library.history.count == 1)
        #expect(fixture.session.archivedScratchCount == 1)
    }

    // MARK: - ⌘S

    @Test("AC-14: 書きかけを ⌘S で下書きにすると、別の文章を開いても ⌘N でも挿入していない履歴は増えない",
          arguments: [false, true])
    func savedScratchIsNotArchived(_ switchesToNewScratch: Bool) throws {
        let fixture = SessionFixture()
        let other = try fixture.addDraft("other")
        fixture.panel.text = "abc"
        fixture.session.saveCurrent()

        if switchesToNewScratch {
            fixture.session.request(.newScratch)
        } else {
            fixture.session.request(.draft(other.id))
        }

        #expect(fixture.library.history.isEmpty)
        #expect(fixture.session.archivedScratchCount == 0)
        #expect(fixture.library.drafts.map(\.text).contains("abc"))
    }

    @Test("AC-14: 履歴の写しを書き換えて ⌘S で下書きにした後は、⌘N でも挿入していない履歴は増えない")
    func savedEditedCopyIsNotArchived() throws {
        let fixture = SessionFixture()
        fixture.library.recordInsertion(text: "orig", appName: "Notes", bundleIdentifier: nil)
        let original = try #require(fixture.library.history.first)
        fixture.session.request(.history(original.id))
        fixture.panel.text = "orig, edited"
        fixture.session.saveCurrent()

        fixture.session.request(.newScratch)

        #expect(fixture.library.history == [original])
        #expect(fixture.session.archivedScratchCount == 0)
    }

    // MARK: - 終了

    @Test("AC-16: 終了するとき、書きかけがあれば挿入していない履歴に残り、保存先にも書き出される")
    func terminationArchivesScratch() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "abc"

        fixture.controller.prepareForTermination()

        let entry = try #require(fixture.reloadedLibrary().history.first)
        #expect(entry.text == "abc")
        #expect(!entry.isInserted)
        #expect(fixture.reloadedLibrary().history.count == 1)
        #expect(fixture.session.archivedScratchCount == 0)
    }

    @Test("AC-16: 終了するとき、書き換え途中の下書きは保存先に書き出され、履歴には移らない")
    func terminationFlushesDraftWithoutArchiving() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        let draft = try #require(fixture.library.addDraft(text: "one"))
        fixture.model.present(target: nil)
        fixture.session.request(.draft(draft.id))
        fixture.model.text = "two"
        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "one")

        fixture.controller.prepareForTermination()

        #expect(fixture.reloadedLibrary().draft(id: draft.id)?.text == "two")
        #expect(fixture.reloadedLibrary().history.isEmpty)
    }

    @Test("AC-16: 終了するとき、空白だけの書きかけは履歴に残さない")
    func terminationIgnoresBlankScratch() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanup() }
        fixture.model.present(target: nil)
        fixture.model.text = "  \n "

        fixture.controller.prepareForTermination()

        #expect(fixture.reloadedLibrary().history.isEmpty)
    }

    // MARK: - 履歴が上限のとき

    @Test("AC-34: 履歴が上限ちょうどでも、最も古い履歴の行を開くとその文章が出て、書きかけは挿入していない履歴に1件だけ入る")
    func openingOldestHistoryAtLimitSwitchesAndArchivesOnce() throws {
        let fixture = SessionFixture(historyLimit: 10)
        for index in 1...10 {
            fixture.library.recordInsertion(text: "past \(index)", appName: "Notes", bundleIdentifier: nil)
        }
        #expect(fixture.library.history.count == 10)
        let oldest = try #require(fixture.library.history.last)
        #expect(oldest.text == "past 1")
        fixture.panel.text = "abc"

        fixture.session.request(.history(oldest.id))

        #expect(fixture.panel.text == "past 1")
        #expect(fixture.session.document == .fromHistory(oldest.id))
        #expect(fixture.library.history.count == 10)
        #expect(fixture.library.history.filter { $0.text == "abc" }.count == 1)
        #expect(fixture.library.history.first?.text == "abc")
        #expect(fixture.library.historyEntry(id: oldest.id) == nil)
        #expect(fixture.session.archivedScratchCount == 1)

        fixture.session.request(.newScratch)

        #expect(fixture.library.history.filter { $0.text == "abc" }.count == 1)
        #expect(fixture.library.history.count == 10)
        #expect(fixture.session.archivedScratchCount == 1)
    }
}
