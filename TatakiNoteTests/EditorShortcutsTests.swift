import Testing
@testable import TatakiNote

@MainActor
struct EditorShortcutsTests {
    @Test("AC-7: ショートカットキーの一覧は7行で、行の入れ替え・複製・行ごとのコピー・切り取り・貼り付け・行と単語の選択のキーがあり、改行・閉じる・確定・確定+送信のキーは入らない")
    func listsEditingShortcuts() {
        let shortcuts = EditorShortcuts.all

        #expect(shortcuts.count == 7)
        #expect(Set(shortcuts.map(\.id)).count == 7)
        for keys in ["⌥↑", "⌥↓", "⇧⌥↑", "⇧⌥↓", "⌘C", "⌘X", "⌘V", "⌘L", "⌘D"] {
            #expect(shortcuts.contains { $0.keys.contains(keys) }, "\(keys)")
        }
        #expect(shortcuts.allSatisfy { !$0.keys.isEmpty && !$0.action.isEmpty })

        for keys in ["↩", "esc", "⌘↩", "⇧⌘↩"] {
            #expect(!shortcuts.contains { $0.keys.contains(keys) }, "\(keys)")
        }
    }

    @Test("AC-15: パネルの操作の行は ⌘K(下書きと履歴を検索する)・⌘S(下書きに保存する)・⌘N(新しい書きかけにする)・⌘E(インサートとノートを切り替える)・⌘B(サイドバーを開く・閉じる)・⌘,(設定を開く)・⇧⌘S(ファイルに書き出す)の7行で、編集キーの7行は変わらない")
    func listsPanelCommandShortcuts() {
        let commands = EditorShortcuts.panelCommands

        #expect(commands.map(\.keys) == ["⌘K", "⌘S", "⌘N", "⌘E", "⌘B", "⌘,", "⇧⌘S"])
        #expect(commands.map(\.id) == ["searchDrafts", "saveDraft", "newDraft", "toggleMode", "toggleSidebar", "openSettings", "exportToFile"])
        #expect(commands[0].action.contains("検索"))
        #expect(commands[1].action.contains("下書きに保存"))
        #expect(commands[2].action.contains("新しい書きかけ"))
        #expect(commands[3].action == "インサートとノートを切り替える")
        #expect(commands[4].action.contains("サイドバー"))
        #expect(commands[5].action.contains("設定"))
        #expect(commands[6].action == "ファイルに書き出す")
        #expect(Set(commands.map(\.id)).isDisjoint(with: EditorShortcuts.all.map(\.id)))
        #expect(EditorShortcuts.all.count == 7)
        #expect(EditorShortcuts.all.allSatisfy { !["⌘K", "⌘S", "⌘N", "⌘E", "⌘B", "⌘,", "⇧⌘S"].contains($0.keys) })
    }

    @Test("AC-18: ⌘, の説明は「設定を開く」で、パネルを閉じるとは書かない")
    func openSettingsShortcutDoesNotMentionClosingPanel() throws {
        let shortcut = try #require(EditorShortcuts.panelCommands.first { $0.id == "openSettings" })

        #expect(shortcut.action == "設定を開く")
        #expect(!shortcut.action.contains("閉じる"))
    }

    @Test("AC-15: パネルの中で使えるキーは「行の操作」「コピーと貼り付け」「下書き」「表示」の4つに分かれ、「下書き」に ⇧⌘S(ファイルに書き出す)が入り、一覧の14行がちょうど1回ずつ、今のキーと文言のまま入る")
    func groupsCoverEveryShortcutExactlyOnce() {
        let groups = EditorShortcuts.groups

        #expect(groups.map(\.title) == ["行の操作", "コピーと貼り付け", "下書き", "表示"])
        #expect(groups.map { $0.shortcuts.map(\.id) } == [
            ["moveLine", "duplicateLine", "selectLine", "selectWord"],
            ["copyLine", "cutLine", "pasteLine"],
            ["saveDraft", "exportToFile", "newDraft", "toggleMode", "searchDrafts"],
            ["toggleSidebar", "openSettings"],
        ])

        let grouped = groups.flatMap(\.shortcuts)
        let source = EditorShortcuts.all + EditorShortcuts.panelCommands
        #expect(grouped.count == 14)
        #expect(grouped.first { $0.id == "exportToFile" }?.keys == "⇧⌘S")
        #expect(Set(grouped.map(\.id)) == Set(source.map(\.id)))
        #expect(Set(groups.map(\.id)).count == 4)
        for shortcut in grouped {
            #expect(source.contains(shortcut), "\(shortcut.id)")
        }
    }

    @Test("AC-25: 「パネルの中で使えるキー」の下の説明文は、いつも決めた全文")
    func settingDescriptionIsExact() {
        #expect(EditorShortcuts.settingDescription == "割り当ては変えられません。確定のキーは上の「確定+挿入キー」「確定+送信キー」で確かめられます。")
    }

    @Test("AC-5: 「ショートカットキー」の説明文は、割り当ては変えられないことと、確定のキーは「確定+挿入キー」「確定+送信キー」で確かめられることを書き、「一般」「エディタ設定」を書かない")
    func settingDescriptionPointsToKeysInSameSection() {
        let description = EditorShortcuts.settingDescription

        for phrase in ["割り当ては変えられません", "確定+挿入キー", "確定+送信キー"] {
            #expect(description.contains(phrase), "\(phrase)")
        }
        for phrase in ["一般", "エディタ設定"] {
            #expect(!description.contains(phrase), "\(phrase)")
        }
    }
}
