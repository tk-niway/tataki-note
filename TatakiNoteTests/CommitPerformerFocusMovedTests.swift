import ApplicationServices
import Testing
@testable import TatakiNote

@MainActor
struct CommitPerformerFocusMovedTests {
    private let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

    private func makePerformer(model: PanelModel, inserter: InserterStub) -> CommitPerformer {
        CommitPerformer(model: model, permission: PermissionStub(isTrusted: true), inserter: inserter)
    }

    @Test("AC-6: 挿入の結果が focusMoved なら、確定した文章がパネルの本文に戻り、確定の結果は focusMoved になる", arguments: [false, true])
    func focusMovedRestoresDraft(shouldSend: Bool) async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "committed"
        let inserter = InserterStub(result: .focusMoved)
        let performer = makePerformer(model: model, inserter: inserter)

        let outcome = await performer.perform(
            model.prepareCommit(isAccessibilityTrusted: true),
            shouldSendAfterInsert: shouldSend
        )

        #expect(outcome == .focusMoved)
        #expect(inserter.calls.count == 1)
        #expect(inserter.calls.first?.shouldSendAfterInsert == shouldSend)
        #expect(model.isPresented == false)
        #expect(model.text == "committed")
    }

    @Test("AC-6: 戻している間に新しい文章を書き始めていれば、本文を上書きしない")
    func focusMovedKeepsNewText() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "committed"
        let inserter = InserterStub(result: .focusMoved)
        inserter.onInsert = { model.text = "new" }
        let performer = makePerformer(model: model, inserter: inserter)

        let outcome = await performer.perform(model.prepareCommit(isAccessibilityTrusted: true))

        #expect(outcome == .focusMoved)
        #expect(model.text == "new")
    }

    @Test("AC-6: focusMoved の結果は、挿入できたことにも履歴に残すことにもならない")
    func focusMovedIsNotInsertion() {
        #expect(CommitOutcome.focusMoved.didInsert == false)
        #expect(CommitOutcome.focusMoved.recordsHistory == false)
    }

    @Test("AC-8: 渡された入力欄は、そのまま挿入に渡る。渡さなければ nil が渡る")
    func passesExpectedFieldToInserter() async {
        let field = AXUIElementCreateApplication(pid_t.max)
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "hello"
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: true), expectedField: field)
        model.present(target: textEdit)
        model.text = "again"
        await performer.perform(model.prepareCommit(isAccessibilityTrusted: true))

        #expect(inserter.expectedFields.count == 2)
        #expect(inserter.expectedFields[0].map { CFEqual($0, field) } == true)
        #expect(inserter.expectedFields[1] == nil)
    }
}
