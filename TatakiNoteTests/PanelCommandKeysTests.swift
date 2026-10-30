import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelCommandKeysTests {
    private struct ExpectedRow {
        let action: PanelKeyAction
        let modifiers: NSEvent.ModifierFlags
        let character: String
        let keyText: String
        let listingID: String
        let listingAction: String
        let operationName: String
    }

    private static let expectedRows: [ExpectedRow] = [
        ExpectedRow(
            action: .openSearch, modifiers: [.command], character: "k", keyText: "⌘K",
            listingID: "searchDrafts", listingAction: "下書きと履歴を検索する(サイドバーを開く)", operationName: "検索"
        ),
        ExpectedRow(
            action: .saveDraft, modifiers: [.command], character: "s", keyText: "⌘S",
            listingID: "saveDraft", listingAction: "下書きに保存する", operationName: "下書きの保存"
        ),
        ExpectedRow(
            action: .newDraft, modifiers: [.command], character: "n", keyText: "⌘N",
            listingID: "newDraft", listingAction: "新しい書きかけにする", operationName: "新しい書きかけ"
        ),
        ExpectedRow(
            action: .toggleMode, modifiers: [.command], character: "e", keyText: "⌘E",
            listingID: "toggleMode", listingAction: "インサートとノートを切り替える", operationName: "モードの切り替え"
        ),
        ExpectedRow(
            action: .toggleSidebar, modifiers: [.command], character: "b", keyText: "⌘B",
            listingID: "toggleSidebar", listingAction: "サイドバーを開く・閉じる", operationName: "サイドバーの開閉"
        ),
        ExpectedRow(
            action: .openSettings, modifiers: [.command], character: ",", keyText: "⌘,",
            listingID: "openSettings", listingAction: "設定を開く", operationName: "設定を開く"
        ),
        ExpectedRow(
            action: .exportToFile, modifiers: [.command, .shift], character: "s", keyText: "⇧⌘S",
            listingID: "exportToFile", listingAction: "ファイルに書き出す", operationName: "ファイルへの書き出し"
        ),
    ]

    private static func input(
        _ character: String,
        modifiers: NSEvent.ModifierFlags,
        hasMarkedText: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: 0, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: character)
    }

    private static func keyEvent(_ character: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: 0
            )
        )
    }

    // MARK: - 表の中身

    @Test("AC-1: 表は7行で、⌘K・⌘S・⌘N・⌘E・⌘B・⌘,・⇧⌘S の順に、今と同じ操作・キー・id・一覧の文言・操作の名前を持つ")
    func tableHasTheSevenRowsInOrder() {
        let rows = PanelCommandKeys.all
        #expect(rows.count == Self.expectedRows.count)
        for (row, expected) in zip(rows, Self.expectedRows) {
            #expect(row.action == expected.action, "\(expected.keyText) の操作")
            #expect(row.key == EditorKeyEquivalent(modifiers: expected.modifiers, character: expected.character), "\(expected.keyText) のキー")
            #expect(row.keyText == expected.keyText)
            #expect(row.listingID == expected.listingID, "\(expected.keyText) の id")
            #expect(row.listingAction == expected.listingAction, "\(expected.keyText) の一覧の文言")
            #expect(row.operationName == expected.operationName, "\(expected.keyText) の操作の名前")
            #expect(row.listing == EditorShortcut(id: expected.listingID, keys: expected.keyText, action: expected.listingAction))
        }
        #expect(PanelCommandKeys.operationNamesText == "検索・下書きの保存・新しい書きかけ・モードの切り替え・サイドバーの開閉・設定を開く・ファイルへの書き出し")
        #expect(PanelCommandKeys.keysText == "⌘K・⌘S・⌘N・⌘E・⌘B・⌘,・⇧⌘S")
    }

    // MARK: - キーを受けて操作を選ぶところ

    @Test("AC-2: 表のどの行のキーを押しても、Caps Lock の印が付いていても、インサートでもノートでも、その行の操作になる")
    func resolverReturnsTheRowAction() {
        for expected in Self.expectedRows {
            for modifiers in [expected.modifiers, expected.modifiers.union(.capsLock)] {
                for mode in [DraftMode.insert, DraftMode.note] {
                    let resolved = PanelKeyResolver.action(
                        for: Self.input(expected.character, modifiers: modifiers),
                        mode: mode
                    )
                    #expect(resolved == expected.action, "\(expected.keyText) \(modifiers) \(mode)")
                }
            }
        }
    }

    @Test("AC-2: 変換中は表のキーも入力メソッドに渡し、表に無い ⌘ のキーは操作にならない")
    func resolverPassesMarkedTextAndUnknownKeysThrough() {
        for expected in Self.expectedRows {
            let resolved = PanelKeyResolver.action(
                for: Self.input(expected.character, modifiers: expected.modifiers, hasMarkedText: true)
            )
            #expect(resolved == .passThrough, "\(expected.keyText) 変換中")
        }
        let unknown: [(String, NSEvent.ModifierFlags)] = [
            ("j", [.command]), ("k", [.command, .shift]), ("s", [.command, .option]), ("", [.command]), ("s", []),
        ]
        for (character, modifiers) in unknown {
            let resolved = PanelKeyResolver.action(for: Self.input(character, modifiers: modifiers))
            #expect(resolved == .passThrough, "\(modifiers) \(character)")
            #expect(PanelCommandKeys.row(modifiers: modifiers, character: character) == nil, "\(modifiers) \(character)")
        }
    }

    // MARK: - 登録できないキーと、パネルが拾うキー

    @Test("AC-3: 登録できないキーとパネルが拾うキーは表のキーとちょうど同じで、保存値でも表のキーが予約に当たる")
    func reservedAndCapturedKeysMatchTheTable() throws {
        #expect(ReservedPanelKeys.keys == PanelCommandKeys.all.map(\.key))

        let characters = "abcdefghijklmnopqrstuvwxyz,.;/".map(String.init)
        let modifierSets: [NSEvent.ModifierFlags] = [
            [.command], [.command, .shift], [.command, .option], [.command, .control], [.shift], [.option], [],
        ]
        for modifiers in modifierSets {
            for character in characters {
                let inTable = PanelCommandKeys.row(modifiers: modifiers, character: character) != nil
                let captured = try PromptPanel.panelCommandInput(
                    for: Self.keyEvent(character, modifiers: modifiers),
                    hasMarkedText: false
                )
                #expect((captured != nil) == inTable, "拾うキー \(modifiers) \(character)")
                #expect(ReservedPanelKeys.contains(modifiers: modifiers, character: character) == inTable, "予約 \(modifiers) \(character)")
            }
        }

        let keyCodes: [String: UInt16] = ["k": 40, "s": 1, "n": 45, "e": 14, "b": 11, ",": 43]
        for expected in Self.expectedRows {
            let keyCode = try #require(keyCodes[expected.character])
            let shortcut = PanelShortcut(keyCode: keyCode, modifiers: expected.modifiers)
            #expect(ReservedPanelKeys.isReserved(shortcut), "保存値 \(expected.keyText)")
        }
        #expect(!ReservedPanelKeys.isReserved(PanelShortcut(keyCode: 40, modifiers: [.command, .shift])))
        #expect(!ReservedPanelKeys.isReserved(PanelShortcut(keyCode: 38, modifiers: [.command])))
    }

    // MARK: - 設定の一覧

    @Test("AC-4: 一覧のパネルの操作の行は表の並びのまま今と同じ id・キー・文言で、4つの分類の中身も変わらない")
    func listingRowsAndGroupsAreUnchanged() {
        let expectedListing = Self.expectedRows.map {
            EditorShortcut(id: $0.listingID, keys: $0.keyText, action: $0.listingAction)
        }
        #expect(EditorShortcuts.panelCommands == expectedListing)

        let groupIDs = EditorShortcuts.groups.map { group in (group.id, group.shortcuts.map(\.id)) }
        let expectedGroups: [(String, [String])] = [
            ("line", ["moveLine", "duplicateLine", "selectLine", "selectWord"]),
            ("clipboard", ["copyLine", "cutLine", "pasteLine"]),
            ("drafts", ["saveDraft", "exportToFile", "newDraft", "toggleMode", "searchDrafts"]),
            ("view", ["toggleSidebar", "openSettings"]),
        ]
        #expect(groupIDs.count == expectedGroups.count)
        for (actual, expected) in zip(groupIDs, expectedGroups) {
            #expect(actual.0 == expected.0)
            #expect(actual.1 == expected.1, "分類 \(expected.0)")
        }

        let drafts = EditorShortcuts.groups.first { $0.id == "drafts" }?.shortcuts ?? []
        #expect(drafts.map(\.keys) == ["⌘S", "⇧⌘S", "⌘N", "⌘E", "⌘K"])
        let view = EditorShortcuts.groups.first { $0.id == "view" }?.shortcuts ?? []
        #expect(view.map(\.keys) == ["⌘B", "⌘,"])
    }

    // MARK: - 登録できないときの説明

    @Test("AC-5: パネルの操作のキーを記録したときの説明は、今と一字も変わらない")
    func rejectionMessageIsUnchanged() {
        let shortcut = PanelShortcut(keyCode: 40, modifiers: [.command])
        let message = PanelShortcutRejection.reservedForPanelCommands.message(for: shortcut)
        #expect(message == "⌘K はパネルの検索・下書きの保存・新しい書きかけ・モードの切り替え・サイドバーの開閉・設定を開く・ファイルへの書き出しの操作(⌘K・⌘S・⌘N・⌘E・⌘B・⌘,・⇧⌘S)で使っているため、登録できません。")
    }

    // MARK: - ほかのキーとの重なり

    @Test("AC-6: 表の操作・キー・id・操作の名前は重ならず、どのキーも ⌘ を含み、編集キー・⌘H・確定のキーの初期値とぶつからない")
    func tableRowsAreDistinctAndDoNotCollide() {
        let rows = PanelCommandKeys.all
        #expect(Set(rows.map(\.listingID)).count == rows.count)
        #expect(Set(rows.map(\.operationName)).count == rows.count)
        #expect(Set(rows.map(\.keyText)).count == rows.count)
        for (index, row) in rows.enumerated() {
            for other in rows[(index + 1)...] {
                #expect(row.action != other.action)
                #expect(row.key != other.key)
            }
        }

        let editorKeys = EditorKeyCommand.allCases.compactMap(\.keyEquivalent)
        let initialKeys = [PanelShortcut.defaultCommitKey, PanelShortcut.defaultCommitAndSendKey].compactMap { $0 }
        for row in rows {
            #expect(row.key.modifiers.contains(.command), "\(row.keyText) は ⌘ を含む")
            #expect(!editorKeys.contains(row.key), "\(row.keyText) は編集キーとぶつからない")
            #expect(row.key != EditorKeyEquivalent(modifiers: [.command], character: "h"), "\(row.keyText) は ⌘H とぶつからない")
            #expect(
                !EditorKeyCommand.isReservedKeyEquivalent(modifiers: row.key.modifiers, character: row.key.character),
                "\(row.keyText) は編集キーの予約に当たらない"
            )
            for initialKey in initialKeys {
                #expect(!ReservedPanelKeys.isReserved(initialKey))
                #expect(initialKey.displayText != row.keyText)
            }
        }
    }
}
