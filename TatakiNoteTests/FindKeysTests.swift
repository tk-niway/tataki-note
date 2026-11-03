import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct FindKeysTests {
    private static func input(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        characters: String = "",
        hasMarkedText: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: characters)
    }

    private static func action(
        _ input: PanelKeyInput,
        focus: FindFocus,
        isBarVisible: Bool = true,
        isReplaceShown: Bool = true
    ) -> FindKeyAction? {
        FindKeyResolver.action(for: input, focus: focus, isBarVisible: isBarVisible, isReplaceShown: isReplaceShown)
    }

    private static let esc = KeyCode.escape
    private static let returnKey = KeyCode.returnKey
    private static let enter = KeyCode.keypadEnter
    private static let tab = KeyCode.tab
    private static let down = KeyCode.downArrow

    private struct GlobalCase {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let characters: String
        let action: FindKeyAction
        let keyText: String
    }

    private static let globalCases: [GlobalCase] = [
        GlobalCase(keyCode: 3, modifiers: [.command], characters: "f", action: .open(revealsReplace: false), keyText: "⌘F"),
        GlobalCase(keyCode: 3, modifiers: [.command, .option], characters: "f", action: .open(revealsReplace: true), keyText: "⌥⌘F"),
        GlobalCase(keyCode: 5, modifiers: [.command], characters: "g", action: .next, keyText: "⌘G"),
        GlobalCase(keyCode: 5, modifiers: [.command, .shift], characters: "g", action: .previous, keyText: "⇧⌘G"),
        GlobalCase(keyCode: 8, modifiers: [.command, .option], characters: "c", action: .toggle(.caseSensitive), keyText: "⌥⌘C"),
        GlobalCase(keyCode: 13, modifiers: [.command, .option], characters: "w", action: .toggle(.wholeWord), keyText: "⌥⌘W"),
        GlobalCase(keyCode: 15, modifiers: [.command, .option], characters: "r", action: .toggle(.regex), keyText: "⌥⌘R"),
        GlobalCase(keyCode: 35, modifiers: [.command, .option], characters: "p", action: .toggle(.preserveCase), keyText: "⌥⌘P"),
        GlobalCase(keyCode: 18, modifiers: [.command, .shift], characters: "!", action: .replaceOne, keyText: "⇧⌘1"),
        GlobalCase(keyCode: 36, modifiers: [.command, .option], characters: "\r", action: .replaceAll, keyText: "⌥⌘↩"),
    ]

    // MARK: - 表

    @Test("AC-12: 検索のキーの表は10行で、⌘F・⌥⌘F・⌘G・⇧⌘G・⌥⌘C・⌥⌘W・⌥⌘R・⌥⌘P・⇧⌘1・⌥⌘↩ の順に操作と表記を持ち、修飾キーは ⌘⌥⇧⌃ の中に収まる")
    func tableHasTheTenRowsInOrder() {
        #expect(FindKeys.global.count == Self.globalCases.count)
        for (row, expected) in zip(FindKeys.global, Self.globalCases) {
            #expect(row.action == expected.action, "\(expected.keyText)")
            #expect(row.modifiers == expected.modifiers, "\(expected.keyText)")
            #expect(row.keyText == expected.keyText)
            #expect(row.modifiers.subtracting(PanelShortcut.relevantModifiers).isEmpty, "\(expected.keyText)")
        }
        #expect(FindKeys.keysText == "⌘F・⌥⌘F・⌘G・⇧⌘G・⌥⌘C・⌥⌘W・⌥⌘R・⌥⌘P・⇧⌘1・⌥⌘↩")
        #expect(Set(FindKeys.global.map(\.keyText)).count == FindKeys.global.count)
    }

    @Test("AC-12: 検索のキーの行は、キーコードや文字・修飾キーが少し違うと当たらず、Caps Lock と fn の印は無視し、テンキーの Enter も ⌥⌘↩ になる")
    func globalKeyMatchesExactly() {
        for expected in Self.globalCases {
            let pressed = Self.input(expected.keyCode, expected.modifiers, characters: expected.characters)
            #expect(FindKeys.globalKey(for: pressed)?.action == expected.action, "\(expected.keyText)")
            let withCaps = Self.input(expected.keyCode, expected.modifiers.union([.capsLock, .function]), characters: expected.characters)
            #expect(FindKeys.globalKey(for: withCaps)?.action == expected.action, "\(expected.keyText) Caps Lock")
        }
        #expect(FindKeys.globalKey(for: Self.input(3, [.command], characters: "F"))?.action == .open(revealsReplace: false))
        #expect(FindKeys.globalKey(for: Self.input(Self.enter, [.command, .option], characters: "\r"))?.action == .replaceAll)

        let notRows: [PanelKeyInput] = [
            Self.input(3, [.command, .shift], characters: "f"),
            Self.input(3, [], characters: "f"),
            Self.input(3, [.command, .control], characters: "f"),
            Self.input(5, [.command, .option], characters: "g"),
            Self.input(8, [.command], characters: "c"),
            Self.input(18, [.command], characters: "1"),
            Self.input(18, [.command, .option], characters: "1"),
            Self.input(Self.returnKey, [.command]),
            Self.input(Self.returnKey, [.command, .shift]),
            Self.input(Self.returnKey, [.option]),
            Self.input(38, [.command], characters: "j"),
            Self.input(40, [.command], characters: "k"),
        ]
        for pressed in notRows {
            #expect(FindKeys.globalKey(for: pressed) == nil, "\(pressed.modifiers) \(pressed.keyCode)")
        }
    }

    @Test("AC-12: 保存値と記録のキーの判定は、検索のキーだけに当たる")
    func reservedChecksMatchOnlyFindKeys() {
        for expected in Self.globalCases {
            let shortcut = PanelShortcut(keyCode: expected.keyCode, modifiers: expected.modifiers)
            #expect(FindKeys.isReserved(PanelShortcutCandidate(shortcut: shortcut, characters: expected.characters)), "\(expected.keyText)")
        }
        #expect(FindKeys.isReserved(PanelShortcut(keyCode: 3, modifiers: [.command])))
        #expect(FindKeys.isReserved(PanelShortcut(keyCode: 3, modifiers: [.command, .option])))
        #expect(FindKeys.isReserved(PanelShortcut(keyCode: 5, modifiers: [.command, .shift])))
        #expect(FindKeys.isReserved(PanelShortcut(keyCode: 18, modifiers: [.command, .shift])))
        #expect(FindKeys.isReserved(PanelShortcut(keyCode: KeyCode.keypadEnter, modifiers: [.command, .option])))

        let notFind: [PanelShortcut] = [
            PanelShortcut(keyCode: 3, modifiers: [.command, .shift]),
            PanelShortcut(keyCode: 5, modifiers: [.command, .option]),
            PanelShortcut(keyCode: 18, modifiers: [.command]),
            PanelShortcut(keyCode: 38, modifiers: [.command]),
            PanelShortcut.commandReturn,
            PanelShortcut.commandShiftReturn,
            PanelShortcut.shiftReturn,
        ]
        for shortcut in notFind {
            #expect(!FindKeys.isReserved(shortcut), "\(shortcut.modifiers) \(shortcut.keyCode)")
            #expect(!FindKeys.isReserved(PanelShortcutCandidate(shortcut: shortcut, characters: "j")))
        }
    }

    // MARK: - 判定の表: どこにフォーカスがあっても効くキー

    @Test("AC-12: 検索のキーは、フォーカスがどこでも、検索バーが出ていてもいなくても、表の操作になる(置換だけは検索バーが出ていなければ何もしない)")
    func globalKeysApplyEverywhere() {
        for focus in [FindFocus.editor, .findField, .replaceField, .other] {
            for isBarVisible in [true, false] {
                for expected in Self.globalCases {
                    let pressed = Self.input(expected.keyCode, expected.modifiers, characters: expected.characters)
                    let resolved = Self.action(pressed, focus: focus, isBarVisible: isBarVisible)
                    switch expected.action {
                    case .replaceOne, .replaceAll:
                        #expect(resolved == (isBarVisible ? expected.action : .swallow), "\(focus) \(isBarVisible) \(expected.keyText)")
                    default:
                        #expect(resolved == expected.action, "\(focus) \(isBarVisible) \(expected.keyText)")
                    }
                }
            }
        }
    }

    // MARK: - 判定の表: 検索欄

    @Test("AC-12: 検索欄の ↩ は次の一致、⇧↩ は前の一致、⌃↩ は欄に改行、⌘↩・⇧⌘↩・⌥↩ は何もせず確定にもしない。テンキーの Enter も同じ")
    func findFieldReturnKeys() {
        for code in [Self.returnKey, Self.enter] {
            #expect(Self.action(Self.input(code), focus: .findField) == .next)
            #expect(Self.action(Self.input(code, [.shift]), focus: .findField) == .previous)
            #expect(Self.action(Self.input(code, [.control]), focus: .findField) == .insertNewlineInField)
            #expect(Self.action(Self.input(code, [.command]), focus: .findField) == .swallow)
            #expect(Self.action(Self.input(code, [.command, .shift]), focus: .findField) == .swallow)
            #expect(Self.action(Self.input(code, [.option]), focus: .findField) == .swallow)
            #expect(Self.action(Self.input(code, [.capsLock]), focus: .findField) == .next)
        }
    }

    @Test("AC-12: 検索欄の Tab は、置換の欄が出ていれば置換欄へ、出ていなければ入力欄へ。⇧Tab は何もしない。⌘↓ は入力欄へ、esc は検索バーを閉じる")
    func findFieldNavigationKeys() {
        #expect(Self.action(Self.input(Self.tab), focus: .findField, isReplaceShown: true) == .focusReplaceField)
        #expect(Self.action(Self.input(Self.tab), focus: .findField, isReplaceShown: false) == .focusEditor)
        #expect(Self.action(Self.input(Self.tab, [.shift]), focus: .findField, isReplaceShown: true) == nil)
        #expect(Self.action(Self.input(Self.tab, [.shift]), focus: .findField, isReplaceShown: false) == nil)
        #expect(Self.action(Self.input(Self.down, [.command]), focus: .findField) == .focusEditor)
        #expect(Self.action(Self.input(Self.down), focus: .findField) == nil)
        #expect(Self.action(Self.input(Self.down, [.command, .shift]), focus: .findField) == nil)
        #expect(Self.action(Self.input(Self.esc), focus: .findField) == .close)
        #expect(Self.action(Self.input(Self.esc, [.shift]), focus: .findField) == nil)
    }

    // MARK: - 判定の表: 置換欄

    @Test("AC-12: 置換欄の ↩ は次を置換、⌘↩ はすべて置換、⌃↩ は欄に改行、⇧↩・⇧⌘↩・⌥↩ は何もせず確定にもしない。テンキーの Enter も同じ")
    func replaceFieldReturnKeys() {
        for code in [Self.returnKey, Self.enter] {
            #expect(Self.action(Self.input(code), focus: .replaceField) == .replaceOne)
            #expect(Self.action(Self.input(code, [.command]), focus: .replaceField) == .replaceAll)
            #expect(Self.action(Self.input(code, [.control]), focus: .replaceField) == .insertNewlineInField)
            #expect(Self.action(Self.input(code, [.shift]), focus: .replaceField) == .swallow)
            #expect(Self.action(Self.input(code, [.command, .shift]), focus: .replaceField) == .swallow)
            #expect(Self.action(Self.input(code, [.option]), focus: .replaceField) == .swallow)
        }
    }

    @Test("AC-12: 置換欄の Tab は入力欄へ、⇧Tab は検索欄へ。⌘↓ は入力欄へ、esc は検索バーを閉じる")
    func replaceFieldNavigationKeys() {
        #expect(Self.action(Self.input(Self.tab), focus: .replaceField) == .focusEditor)
        #expect(Self.action(Self.input(Self.tab, [.shift]), focus: .replaceField) == .focusFindField)
        #expect(Self.action(Self.input(Self.tab, [.command]), focus: .replaceField) == nil)
        #expect(Self.action(Self.input(Self.down, [.command]), focus: .replaceField) == .focusEditor)
        #expect(Self.action(Self.input(Self.esc), focus: .replaceField) == .close)
    }

    @Test("AC-12: 検索欄・置換欄の文字の入力や ⌘K など表に無いキーは検索の操作にならず、今までどおり処理される")
    func fieldKeysOutsideTheTableAreNotFindActions() {
        let others: [PanelKeyInput] = [
            Self.input(0, characters: "a"),
            Self.input(40, [.command], characters: "k"),
            Self.input(38, [.command], characters: "j"),
            Self.input(Self.down, [.option]),
            Self.input(Self.tab, [.control]),
            Self.input(Self.esc, [.command]),
        ]
        for focus in [FindFocus.findField, .replaceField] {
            for pressed in others {
                #expect(Self.action(pressed, focus: focus) == nil, "\(focus) \(pressed.modifiers) \(pressed.keyCode)")
            }
        }
    }

    @Test("AC-12: 検索バーが出ていなければ、検索欄・置換欄にフォーカスがあるはずの状態でも ↩・Tab・esc は検索の操作にならない")
    func fieldKeysWithoutVisibleBarAreNotFindActions() {
        let keys: [PanelKeyInput] = [
            Self.input(Self.returnKey), Self.input(Self.returnKey, [.shift]), Self.input(Self.returnKey, [.command]),
            Self.input(Self.tab), Self.input(Self.tab, [.shift]), Self.input(Self.esc), Self.input(Self.down, [.command]),
        ]
        for focus in [FindFocus.findField, .replaceField] {
            for pressed in keys {
                #expect(Self.action(pressed, focus: focus, isBarVisible: false) == nil, "\(focus) \(pressed.modifiers) \(pressed.keyCode)")
            }
        }
    }

    // MARK: - 判定の表: 入力欄・サイドバー

    @Test("AC-12: 入力欄の esc は、検索バーが出ていれば閉じ、出ていなければ検索の操作にならない(パネルを閉じる今までの処理へ渡す)")
    func editorEscapeClosesTheBarOnlyWhenVisible() {
        #expect(Self.action(Self.input(Self.esc), focus: .editor, isBarVisible: true) == .close)
        #expect(Self.action(Self.input(Self.esc), focus: .editor, isBarVisible: false) == nil)
    }

    @Test("AC-12: 入力欄の ↩・Tab・⌘↓・文字は検索バーが出ていても検索の操作にならず、確定などの今までの処理へ渡る")
    func editorOtherKeysAreNotFindActions() {
        let others: [PanelKeyInput] = [
            Self.input(Self.returnKey), Self.input(Self.returnKey, [.shift]), Self.input(Self.returnKey, [.command, .shift]),
            Self.input(Self.returnKey, [.command]), Self.input(Self.tab), Self.input(Self.tab, [.shift]),
            Self.input(Self.down, [.command]), Self.input(0, characters: "a"), Self.input(40, [.command], characters: "k"),
        ]
        for isBarVisible in [true, false] {
            for pressed in others {
                #expect(Self.action(pressed, focus: .editor, isBarVisible: isBarVisible) == nil, "\(isBarVisible) \(pressed.modifiers) \(pressed.keyCode)")
            }
        }
    }

    @Test("AC-12: サイドバーの一覧・検索欄では、検索バーが出ていても esc・↩・Tab・⌘↓ は検索の操作にならない")
    func otherFocusKeysAreNotFindActions() {
        let keys: [PanelKeyInput] = [
            Self.input(Self.esc), Self.input(Self.returnKey), Self.input(Self.returnKey, [.shift]), Self.input(Self.returnKey, [.command]),
            Self.input(Self.tab), Self.input(Self.tab, [.shift]), Self.input(Self.down, [.command]), Self.input(0, characters: "a"),
        ]
        for isBarVisible in [true, false] {
            for pressed in keys {
                #expect(Self.action(pressed, focus: .other, isBarVisible: isBarVisible) == nil, "\(isBarVisible) \(pressed.modifiers) \(pressed.keyCode)")
            }
        }
    }

    @Test("AC-12: 確定キーに ⌘J のような検索に使わないキーを登録していれば、検索欄・置換欄でも検索の操作にならない")
    func nonFindCommitKeyIsNotAFindAction() {
        let commandJ = Self.input(38, [.command], characters: "j")
        for focus in [FindFocus.findField, .replaceField, .editor] {
            #expect(Self.action(commandJ, focus: focus) == nil, "\(focus)")
        }
    }

    // MARK: - 変換中

    @Test("AC-13: 変換中は、検索のキー・↩・esc・Tab・⌘↓ のどれも検索の操作にせず入力メソッドへ渡す(フォーカスの場所と検索バーの表示によらず)")
    func markedTextPassesEveryKeyThrough() {
        var keys: [PanelKeyInput] = Self.globalCases.map {
            Self.input($0.keyCode, $0.modifiers, characters: $0.characters, hasMarkedText: true)
        }
        keys += [
            Self.input(Self.returnKey, hasMarkedText: true),
            Self.input(Self.returnKey, [.shift], hasMarkedText: true),
            Self.input(Self.returnKey, [.command], hasMarkedText: true),
            Self.input(Self.esc, hasMarkedText: true),
            Self.input(Self.tab, hasMarkedText: true),
            Self.input(Self.tab, [.shift], hasMarkedText: true),
            Self.input(Self.down, [.command], hasMarkedText: true),
        ]
        for focus in [FindFocus.editor, .findField, .replaceField, .other] {
            for isBarVisible in [true, false] {
                for pressed in keys {
                    #expect(
                        Self.action(pressed, focus: focus, isBarVisible: isBarVisible) == nil,
                        "\(focus) \(isBarVisible) \(pressed.modifiers) \(pressed.keyCode)"
                    )
                }
            }
        }
    }

    @Test("AC-13: 変換が終われば、同じキーが表どおりの操作になる")
    func sameKeysApplyAfterMarkedTextEnds() {
        #expect(Self.action(Self.input(Self.returnKey, hasMarkedText: false), focus: .findField) == .next)
        #expect(Self.action(Self.input(Self.esc, hasMarkedText: false), focus: .replaceField) == .close)
        #expect(Self.action(Self.input(3, [.command], characters: "f", hasMarkedText: false), focus: .editor) == .open(revealsReplace: false))
    }

    // MARK: - 欄の編集のキー

    @Test("AC-43: 検索欄・置換欄を編集中なら、⌘X・⌘C・⌘V・⌘A・⌘Z・⇧⌘Z が欄の編集の操作になる")
    func fieldEditActionMatchesEditingKeys() {
        let cases: [(NSEvent.ModifierFlags, String, FieldEditAction)] = [
            ([.command], "x", .cut), ([.command], "c", .copy), ([.command], "v", .paste),
            ([.command], "a", .selectAll), ([.command], "z", .undo), ([.command, .shift], "z", .redo),
        ]
        for (modifiers, character, expected) in cases {
            let resolved = FindKeys.fieldEditAction(modifiers: modifiers, character: character, isEditing: true, hasMarkedText: false)
            #expect(resolved == expected, "\(modifiers) \(character)")
            let withCaps = FindKeys.fieldEditAction(modifiers: modifiers.union(.capsLock), character: character, isEditing: true, hasMarkedText: false)
            #expect(withCaps == expected, "Caps Lock \(modifiers) \(character)")
        }
    }

    @Test("AC-43: 欄を編集中でないとき・変換中・⌘L・⌥⌘V・修飾キーなしの v は欄の編集の操作にならない")
    func fieldEditActionIsNilOutsideEditing() {
        for (modifiers, character) in [
            (NSEvent.ModifierFlags([.command]), "x"), ([.command], "v"), ([.command, .shift], "z"),
        ] {
            #expect(FindKeys.fieldEditAction(modifiers: modifiers, character: character, isEditing: false, hasMarkedText: false) == nil)
            #expect(FindKeys.fieldEditAction(modifiers: modifiers, character: character, isEditing: true, hasMarkedText: true) == nil)
            #expect(FindKeys.fieldEditAction(modifiers: modifiers, character: character, isEditing: false, hasMarkedText: true) == nil)
        }
        let others: [(NSEvent.ModifierFlags, String)] = [
            ([.command], "l"), ([.command], "d"), ([.command, .option], "v"), ([], "v"), ([.shift], "v"), ([.command], "k"),
        ]
        for (modifiers, character) in others {
            #expect(
                FindKeys.fieldEditAction(modifiers: modifiers, character: character, isEditing: true, hasMarkedText: false) == nil,
                "\(modifiers) \(character)"
            )
        }
    }
}
