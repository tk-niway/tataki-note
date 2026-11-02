import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DraftSessionFocusMovedTests {
    private static let ownProcessIdentifier: pid_t = 777
    private static let safari = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

    @MainActor
    private final class Fixture {
        let panel = PanelModel()
        let library = DraftLibrary(store: .inMemory)
        let session: DraftSession

        init() {
            session = DraftSession(
                panel: panel,
                library: library,
                ownProcessIdentifier: DraftSessionFocusMovedTests.ownProcessIdentifier
            )
            panel.present(target: DraftSessionFocusMovedTests.safari)
        }

        func commit() -> CommitPlan {
            session.prepareCommit { panel.prepareCommit(isAccessibilityTrusted: true) }
        }

        func savedDraftID() -> UUID? {
            if case .savedDraft(let id) = session.document { return id }
            return nil
        }
    }

    @Test("AC-11: フォーカスが移って挿入しなかった文章は、履歴に残らない")
    func focusMovedIsNotRecorded() {
        let fixture = Fixture()
        fixture.panel.text = "unmoved"

        let plan = fixture.commit()
        #expect(fixture.panel.restoreDraft("unmoved"))
        fixture.session.finishCommit(plan, outcome: .focusMoved)

        #expect(fixture.library.history.isEmpty)
        #expect(fixture.panel.text == "unmoved")
        #expect(fixture.session.document == .scratch)
    }

    @Test("AC-11: 保存した下書きから確定してフォーカスが移っていたら、同じ下書きを開いた状態に戻る")
    func focusMovedRestoresSavedDraftDocument() throws {
        let fixture = Fixture()
        fixture.panel.text = "retry me"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.restoreDraft("retry me"))
        fixture.session.finishCommit(plan, outcome: .focusMoved)

        #expect(fixture.session.document == .savedDraft(id))
        #expect(fixture.library.history.isEmpty)
    }

    @Test("AC-11: 履歴から読み込んだ文章を確定してフォーカスが移っていたら、履歴から読み込んだ状態に戻り、履歴は増えない")
    func focusMovedRestoresFromHistoryDocument() {
        let fixture = Fixture()
        fixture.library.recordInsertion(text: "past text", appName: nil, bundleIdentifier: nil)
        let id = fixture.library.history[0].id
        fixture.session.request(.history(id))

        let plan = fixture.commit()
        #expect(fixture.session.document == .scratch)
        #expect(fixture.panel.restoreDraft("past text"))
        fixture.session.finishCommit(plan, outcome: .focusMoved)

        #expect(fixture.session.document == .fromHistory(id))
        #expect(fixture.library.history.count == 1)
    }

    @Test("AC-11: 戻した後に別の文章を書き始めていれば、保存していない書きかけのまま")
    func focusMovedWithNewTextStaysScratch() throws {
        let fixture = Fixture()
        fixture.panel.text = "old"
        fixture.session.saveCurrent()
        let id = try #require(fixture.savedDraftID())

        let plan = fixture.commit()
        fixture.panel.text = "new text"
        #expect(!fixture.panel.restoreDraft("old"))
        fixture.session.finishCommit(plan, outcome: .focusMoved)

        #expect(fixture.session.document == .scratch)
        #expect(fixture.library.draft(id: id)?.text == "old")
        #expect(fixture.library.history.isEmpty)
    }
}
