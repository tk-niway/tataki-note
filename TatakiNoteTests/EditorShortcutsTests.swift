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

    @Test("AC-15: パネルの中で使えるキーは「行の操作」「コピーと貼り付け」「下書き」「検索と置換」「表示」の5つに分かれ、「下書き」に ⇧⌘S(ファイルに書き出す)が入り、一覧の23行がちょうど1回ずつ、今のキーと文言のまま入る")
    func groupsCoverEveryShortcutExactlyOnce() {
        let groups = EditorShortcuts.groups

        #expect(groups.map(\.title) == ["行の操作", "コピーと貼り付け", "下書き", "検索と置換", "表示"])
        #expect(groups.map { $0.shortcuts.map(\.id) } == [
            ["moveLine", "duplicateLine", "selectLine", "selectWord"],
            ["copyLine", "cutLine", "pasteLine"],
            ["saveDraft", "exportToFile", "newDraft", "toggleMode", "searchDrafts"],
            ["findOpen", "findReplaceOpen", "findNext", "findPrevious", "findToggleOptions", "findPreserveCase", "findReplaceOne", "findReplaceAll", "findClose"],
            ["toggleSidebar", "openSettings"],
        ])

        let grouped = groups.flatMap(\.shortcuts)
        let source = EditorShortcuts.all + EditorShortcuts.panelCommands + EditorShortcuts.find
        #expect(grouped.count == 23)
        #expect(grouped.first { $0.id == "exportToFile" }?.keys == "⇧⌘S")
        #expect(Set(grouped.map(\.id)) == Set(source.map(\.id)))
        #expect(Set(groups.map(\.id)).count == 5)
        for shortcut in grouped {
            #expect(source.contains(shortcut), "\(shortcut.id)")
        }
    }

    @Test("AC-17: 「下書き」の次に「検索と置換」の分類が加わり、検索のキーの9行が表のキーと文言のまま並び、既存の4つの分類と行は変わらない")
    func findGroupFollowsDraftsWithTheFindRows() throws {
        let groups = EditorShortcuts.groups
        let draftsIndex = try #require(groups.firstIndex { $0.id == "drafts" })
        let find = groups[draftsIndex + 1]

        #expect(find.id == "find")
        #expect(find.title == "検索と置換")
        #expect(find == EditorShortcutGroup(id: "find", title: "検索と置換", shortcuts: EditorShortcuts.find))
        #expect(find.shortcuts.map(\.id) == ["findOpen", "findReplaceOpen", "findNext", "findPrevious", "findToggleOptions", "findPreserveCase", "findReplaceOne", "findReplaceAll", "findClose"])
        #expect(find.shortcuts.map(\.keys) == ["⌘F", "⌥⌘F", "↩ / ⌘G", "⇧↩ / ⇧⌘G", "⌥⌘C / ⌥⌘W / ⌥⌘R", "⌥⌘P", "⇧⌘1", "⌥⌘↩", "esc"])
        #expect(find.shortcuts.map(\.action) == [
            "検索バーを出す(選択中の文字を検索語にする)",
            "置換の欄まで出す",
            "次の一致へ",
            "前の一致へ",
            "大文字と小文字の区別・単語単位・正規表現を切り替える",
            "置換で大文字と小文字を保持する",
            "次を置換する(置換欄では ↩)",
            "すべて置換する(置換欄では ⌘↩)",
            "検索バーを閉じる",
        ])

        let others = groups.filter { $0.id != "find" }
        #expect(others.map(\.id) == ["line", "clipboard", "drafts", "view"])
        #expect(others.map(\.title) == ["行の操作", "コピーと貼り付け", "下書き", "表示"])
        #expect(others.map { $0.shortcuts.count } == [4, 3, 5, 2])
        #expect(EditorShortcuts.all.count == 7)
        #expect(EditorShortcuts.panelCommands.count == 7)
        #expect(Set(EditorShortcuts.find.map(\.id)).isDisjoint(with: (EditorShortcuts.all + EditorShortcuts.panelCommands).map(\.id)))
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
