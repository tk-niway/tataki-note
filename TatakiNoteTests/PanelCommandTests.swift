import Testing
@testable import TatakiNote

struct PanelCommandTests {
    private struct Procedure: Equatable {
        var commitsMarkedTextFirst: Bool
        var requestsEditorFocusAfterward: Bool
    }

    private static func expectedProcedure(_ command: PanelCommand, from source: PanelCommandSource) -> Procedure {
        switch (command, source) {
        case (.openSettings, _):
            return Procedure(commitsMarkedTextFirst: true, requestsEditorFocusAfterward: false)
        case (.saveDraft, .button):
            return Procedure(commitsMarkedTextFirst: true, requestsEditorFocusAfterward: true)
        case (.close, .button), (.commit, .button), (.commitAndSend, .button), (.newDraft, .button), (.share, .button):
            return Procedure(commitsMarkedTextFirst: true, requestsEditorFocusAfterward: false)
        default:
            return Procedure(commitsMarkedTextFirst: false, requestsEditorFocusAfterward: false)
        }
    }

    @Test("AC-7: 変換中の文字を先に確定するか・後で入力欄へフォーカスを戻すかは、操作と呼び出し元ごとに表のとおり",
          arguments: PanelCommand.allCases, PanelCommandSource.allCases)
    func procedureMatchesTable(command: PanelCommand, source: PanelCommandSource) {
        let expected = Self.expectedProcedure(command, from: source)

        #expect(command.commitsMarkedTextFirst(from: source) == expected.commitsMarkedTextFirst)
        #expect(command.requestsEditorFocusAfterward(from: source) == expected.requestsEditorFocusAfterward)
    }

    @Test("AC-7: 行うかどうかは、ノートの書きかけで帯の挿入・送信のボタンを押したときだけ false",
          arguments: PanelCommand.allCases, PanelCommandSource.allCases)
    func availabilityMatchesTable(command: PanelCommand, source: PanelCommandSource) {
        for mode in DraftMode.allCases {
            let isBlocked = (command == .commit || command == .commitAndSend) && source == .button && mode == .note

            #expect(command.isAvailable(in: mode, from: source) == !isBlocked)
        }
    }

    @Test("AC-8: キーで選ばれた操作は、esc が閉じる・ほかは同じ名前の操作に対応し、改行を入れる・通すは操作にならない")
    func keyActionMapsToCommand() {
        #expect(PanelKeyAction.cancel.command == .close)
        #expect(PanelKeyAction.commit.command == .commit)
        #expect(PanelKeyAction.commitAndSend.command == .commitAndSend)
        #expect(PanelKeyAction.openSearch.command == .openSearch)
        #expect(PanelKeyAction.saveDraft.command == .saveDraft)
        #expect(PanelKeyAction.newDraft.command == .newDraft)
        #expect(PanelKeyAction.toggleMode.command == .toggleMode)
        #expect(PanelKeyAction.toggleSidebar.command == .toggleSidebar)
        #expect(PanelKeyAction.openSettings.command == .openSettings)
        #expect(PanelKeyAction.exportToFile.command == .exportToFile)
        #expect(PanelKeyAction.insertNewline.command == nil)
        #expect(PanelKeyAction.passThrough.command == nil)
    }

    @Test("AC-8: 表のどの行の操作も、対応する操作を持つ")
    func everyTableRowHasCommand() {
        for row in PanelCommandKeys.all {
            #expect(row.action.command != nil)
        }
    }

    @Test("AC-13: 帯の挿入の項目は確定、送信の項目は確定+送信の操作を呼び、閉じる・改行・文字数・行数の項目は操作を持たない")
    func statusItemButtonCommands() {
        #expect(PanelStatusItem.commit.buttonCommand == .commit)
        #expect(PanelStatusItem.commitAndSend.buttonCommand == .commitAndSend)
        #expect(PanelStatusItem.close.buttonCommand == nil)
        #expect(PanelStatusItem.lineBreak.buttonCommand == nil)
        #expect(PanelStatusItem.characterCount.buttonCommand == nil)
        #expect(PanelStatusItem.lineCount.buttonCommand == nil)
    }
}
