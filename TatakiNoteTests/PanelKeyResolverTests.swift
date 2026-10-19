import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelKeyResolverTests {
    @Test("AC-3: 未確定の文字が無いときの Esc はパネルを閉じる")
    func escapeWithoutMarkedTextCancels() {
        let input = PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false)

        #expect(PanelKeyResolver.action(for: input) == .cancel)
    }

    @Test("AC-19: 未確定の文字があるときの Esc・Enter・登録したキーは入力メソッドに渡す(回帰)")
    func markedTextPassesEverythingThrough() {
        let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
        let inputs = [
            PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.shift], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: true),
            PanelKeyInput(keyCode: 40, modifiers: [.command], hasMarkedText: true, characters: "k"),
        ]

        for input in inputs {
            #expect(
                PanelKeyResolver.action(for: input, commitKey: commandK, commitAndSendKey: .shiftReturn) == .passThrough,
                "\(input)"
            )
        }
    }

    @Test("AC-5: Enter(Return・テンキーの Enter)と普通の文字はパネルを閉じず、そのまま入力になる")
    func enterAndCharactersPassThrough() {
        let inputs = [
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [], hasMarkedText: false),
            PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [], hasMarkedText: false),
            PanelKeyInput(keyCode: 0, modifiers: [], hasMarkedText: false),
            PanelKeyInput(keyCode: 0, modifiers: [.shift], hasMarkedText: false),
        ]

        for input in inputs {
            #expect(PanelKeyResolver.action(for: input) == .passThrough, "\(input)")
        }
    }

    // MARK: - 確定キー

    @Test("AC-4, AC-5: 確定キーに選んだキーを押したときだけ確定になり、それ以外の Enter と登録なしのときは入力欄に渡す(Return・テンキーの Enter)")
    func commitKeysDependOnSetting() {
        let pressedKeys: [(NSEvent.ModifierFlags, String)] = [
            ([.shift], "Shift+Enter"),
            ([.command], "⌘Enter"),
            ([.command, .shift], "⌘⇧Enter"),
            ([], "Enter"),
        ]
        let expectations: [(PanelShortcut?, [PanelKeyAction])] = [
            (.shiftReturn, [.commit, .passThrough, .passThrough, .passThrough]),
            (.commandReturn, [.passThrough, .commit, .passThrough, .passThrough]),
            (.commandShiftReturn, [.passThrough, .passThrough, .commit, .passThrough]),
            (nil, [.passThrough, .passThrough, .passThrough, .passThrough]),
        ]

        for (commitKey, expectedActions) in expectations {
            for ((modifiers, keyName), expected) in zip(pressedKeys, expectedActions) {
                for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                    let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                    #expect(
                        PanelKeyResolver.action(for: input, commitKey: commitKey, commitAndSendKey: nil) == expected,
                        "\(String(describing: commitKey)) + \(keyName) + keyCode \(keyCode)"
                    )
                }
            }
        }
    }

    @Test("AC-2: 確定キーを指定しないときは初期値(⇧⌘↩)として判定し、確定+送信キーを指定しないときは初期値(⌘↩)として判定する")
    func defaultCommitKeysAreTheNewDefaults() {
        #expect(PanelShortcut.defaultCommitKey == .commandShiftReturn)
        #expect(PanelShortcut.defaultCommitAndSendKey == .commandReturn)
        let plainReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [], hasMarkedText: false)
        let shiftReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.shift], hasMarkedText: false)
        let commandReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
        let commandShiftReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)

        #expect(PanelKeyResolver.action(for: commandShiftReturn) == .commit)
        #expect(PanelKeyResolver.action(for: commandReturn) == .commitAndSend)
        #expect(PanelKeyResolver.action(for: shiftReturn) == .passThrough)
        #expect(PanelKeyResolver.action(for: plainReturn) == .passThrough)
    }

    @Test("AC-19: 未確定の文字があるときは、どの確定キーの設定でも確定にしない")
    func markedTextNeverCommits() {
        let inputs = [
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.shift], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [.shift], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [.command], hasMarkedText: true),
            PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [.command, .shift], hasMarkedText: true),
        ]
        let commitKeys: [PanelShortcut?] = [nil, .shiftReturn, .commandReturn, .commandShiftReturn]

        for commitKey in commitKeys {
            for input in inputs {
                #expect(
                    PanelKeyResolver.action(for: input, commitKey: commitKey) == .passThrough,
                    "\(String(describing: commitKey)) + \(input)"
                )
            }
        }
    }

    @Test("AC-4: 修飾キーが設定の組み合わせと同じときだけ確定になり、Caps Lock・テンキー・fn の印は影響しない")
    func onlyExactModifiersCommit() {
        let cases: [(PanelShortcut?, NSEvent.ModifierFlags, PanelKeyAction, String)] = [
            (.shiftReturn, [.shift, .capsLock], .commit, "Shift + Caps Lock"),
            (.shiftReturn, [.shift, .function], .commit, "Shift + fn"),
            (.shiftReturn, [.shift, .option], .passThrough, "⇧⌥"),
            (.shiftReturn, [.command, .shift], .passThrough, "⇧⌘"),
            (.commandReturn, [.command, .numericPad], .commit, "⌘ + テンキーの印"),
            (.commandReturn, [.command, .control], .passThrough, "⌃⌘"),
            (.commandReturn, [.command, .shift], .passThrough, "⇧⌘"),
            (.commandShiftReturn, [.command, .shift, .capsLock], .commit, "⇧⌘ + Caps Lock"),
            (.commandShiftReturn, [.command, .shift, .function], .commit, "⇧⌘ + fn"),
            (.commandShiftReturn, [.command, .shift, .option], .passThrough, "⌥⇧⌘"),
            (.commandShiftReturn, [.command], .passThrough, "⌘"),
            (.commandShiftReturn, [.shift], .passThrough, "⇧"),
            (nil, [.command, .capsLock], .passThrough, "⌘ + Caps Lock"),
            (nil, [.shift, .function], .passThrough, "Shift + fn"),
        ]

        for (commitKey, modifiers, expected, label) in cases {
            for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(
                    PanelKeyResolver.action(for: input, commitKey: commitKey, commitAndSendKey: nil) == expected,
                    "\(String(describing: commitKey)) + \(label) + keyCode \(keyCode)"
                )
            }
        }
        let commitKeys: [PanelShortcut?] = [nil, .shiftReturn, .commandReturn, .commandShiftReturn]
        for commitKey in commitKeys {
            for modifiers: NSEvent.ModifierFlags in [[.option], [.control]] {
                let input = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: modifiers, hasMarkedText: false)
                #expect(
                    PanelKeyResolver.action(for: input, commitKey: commitKey, commitAndSendKey: nil) == .passThrough,
                    "\(String(describing: commitKey)) + \(modifiers)"
                )
            }
        }
    }

    @Test("AC-18: 登録したキーは Return 以外でも確定・確定+送信になり、テンキーの Enter は Return と同じに扱う")
    func nonReturnKeysCommitToo() {
        let commandJ = PanelShortcut(keyCode: 38, modifiers: [.command])
        let optionJ = PanelShortcut(keyCode: 38, modifiers: [.option])

        let commandJInput = PanelKeyInput(keyCode: 38, modifiers: [.command], hasMarkedText: false, characters: "j")
        #expect(PanelKeyResolver.action(for: commandJInput, commitKey: commandJ, commitAndSendKey: optionJ) == .commit)

        let optionJInput = PanelKeyInput(keyCode: 38, modifiers: [.option], hasMarkedText: false, characters: "j")
        #expect(PanelKeyResolver.action(for: optionJInput, commitKey: commandJ, commitAndSendKey: optionJ) == .commitAndSend)

        let keypadReturn = PanelKeyInput(keyCode: KeyCode.keypadEnter, modifiers: [.command], hasMarkedText: false)
        #expect(PanelKeyResolver.action(for: keypadReturn, commitKey: .commandReturn, commitAndSendKey: nil) == .commit)
    }

    // MARK: - 確定+送信キー

    private let enterKeys: [(NSEvent.ModifierFlags, String)] = [
        ([.shift], "Shift+Enter"),
        ([.command], "⌘Enter"),
        ([.command, .shift], "⌘⇧Enter"),
        ([], "Enter"),
    ]

    @Test("AC-4, AC-5: 確定+送信に割り当てたキーは挿入して送信する操作、確定に割り当てたキーは挿入だけの操作になり、それ以外は入力欄に渡す(Return・テンキーの Enter)")
    func commitAndSendKeysDependOnSettings() {
        let expectations: [(PanelShortcut?, PanelShortcut?, [PanelKeyAction])] = [
            (.commandReturn, .commandShiftReturn, [.passThrough, .commit, .commitAndSend, .passThrough]),
            (.commandReturn, .shiftReturn, [.commitAndSend, .commit, .passThrough, .passThrough]),
            (.shiftReturn, .commandReturn, [.commit, .commitAndSend, .passThrough, .passThrough]),
            (.commandShiftReturn, .shiftReturn, [.commitAndSend, .passThrough, .commit, .passThrough]),
            (nil, .commandShiftReturn, [.passThrough, .passThrough, .commitAndSend, .passThrough]),
            (nil, .commandReturn, [.passThrough, .commitAndSend, .passThrough, .passThrough]),
            (.commandReturn, nil, [.passThrough, .commit, .passThrough, .passThrough]),
        ]

        for (commitKey, commitAndSendKey, expectedActions) in expectations {
            for ((modifiers, keyName), expected) in zip(enterKeys, expectedActions) {
                for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                    let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                    #expect(
                        PanelKeyResolver.action(for: input, commitKey: commitKey, commitAndSendKey: commitAndSendKey) == expected,
                        "確定 \(String(describing: commitKey)) / 確定+送信 \(String(describing: commitAndSendKey)) + \(keyName) + keyCode \(keyCode)"
                    )
                }
            }
        }

        let capsLockCommandShift = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift, .capsLock], hasMarkedText: false)
        let optionCommandShift = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift, .option], hasMarkedText: false)
        #expect(PanelKeyResolver.action(for: capsLockCommandShift, commitKey: nil, commitAndSendKey: .commandShiftReturn) == .commitAndSend)
        #expect(PanelKeyResolver.action(for: optionCommandShift, commitKey: nil, commitAndSendKey: .commandShiftReturn) == .passThrough)

        let escape = PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false)
        #expect(PanelKeyResolver.action(for: escape, commitKey: nil, commitAndSendKey: .commandShiftReturn) == .cancel)
    }

    @Test("AC-21: 確定にも確定+送信にも登録していない ⌘↩・⇧⌘↩ は、今までどおり入力欄に改行を入れる(回帰)")
    func unassignedCommandEnterInsertsNewline() {
        let commandReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
        let commandShiftReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)

        for input in [commandReturn, commandShiftReturn] {
            #expect(PanelKeyResolver.action(for: input, commitKey: nil, commitAndSendKey: nil) == .passThrough, "\(input)")
            #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input), "\(input)")
        }
    }

    @Test("AC-9: 確定・確定+送信の両方が登録なしなら、Shift+Enter・⌘Enter・⌘⇧Enter・Enter のどれも挿入も送信もせず、改行になる")
    func bothNoneLeavesEveryEnterAsNewline() {
        for (modifiers, keyName) in enterKeys {
            for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(
                    PanelKeyResolver.action(for: input, commitKey: nil, commitAndSendKey: nil) == .passThrough,
                    "\(keyName) + keyCode \(keyCode)"
                )
                let isCommandEnter = modifiers.contains(.command)
                #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input) == isCommandEnter, "\(keyName) + keyCode \(keyCode)")
            }
        }
    }

    @Test("AC-10: 確定と確定+送信に同じキーが保存されていたら、確定(挿入だけ)になり、送信はしない")
    func sameKeyForBothCommitsWithoutSending() {
        let cases: [(PanelShortcut, NSEvent.ModifierFlags)] = [
            (.shiftReturn, [.shift]),
            (.commandReturn, [.command]),
            (.commandShiftReturn, [.command, .shift]),
        ]
        for (key, modifiers) in cases {
            for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(
                    PanelKeyResolver.action(for: input, commitKey: key, commitAndSendKey: key) == .commit,
                    "\(key) + keyCode \(keyCode)"
                )
            }
        }
    }

    @Test("AC-19: 未確定の文字があるときは、確定+送信のキーを押しても、どの設定の組み合わせでも挿入も送信もしない")
    func markedTextNeverCommitsAndSends() {
        let keys: [PanelShortcut?] = [nil, .shiftReturn, .commandReturn, .commandShiftReturn]
        for commitKey in keys {
            for commitAndSendKey in keys {
                for (modifiers, keyName) in enterKeys {
                    for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
                        let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: true)
                        #expect(
                            PanelKeyResolver.action(for: input, commitKey: commitKey, commitAndSendKey: commitAndSendKey) == .passThrough,
                            "確定 \(String(describing: commitKey)) / 確定+送信 \(String(describing: commitAndSendKey)) + 変換中 \(keyName) + keyCode \(keyCode)"
                        )
                    }
                }
            }
        }
    }

    @Test("AC-30: 確定キーに ⇧Esc を渡しても ⇧Esc は cancel になる(Esc は確定より先に調べる。回帰)")
    func shiftEscapeStillCancelsEvenIfAssignedAsCommitKey() {
        let shiftEscapeShortcut = PanelShortcut(keyCode: KeyCode.escape, modifiers: [.shift])
        let input = PanelKeyInput(keyCode: KeyCode.escape, modifiers: [.shift], hasMarkedText: false)

        #expect(PanelKeyResolver.action(for: input, commitKey: shiftEscapeShortcut, commitAndSendKey: nil) == .cancel)
    }

    // MARK: - 検索・保存・新規

    private func commandKey(_ character: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [.command], hasMarkedText: Bool = false) -> PanelKeyInput {
        PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: hasMarkedText, characters: character)
    }

    @Test("AC-9: ⌘K は検索、⌘S は保存、⌘N は新規、⌘E はモードの切り替え、⌘B はサイドバーの開閉、⌘, は設定を開く操作になり、Caps Lock・fn・テンキーの印が付いていても同じ。モードによらない")
    func panelCommandKeys() {
        let cases: [(String, UInt16, PanelKeyAction)] = [
            ("k", 40, .openSearch),
            ("s", 1, .saveDraft),
            ("n", 45, .newDraft),
            ("e", 14, .toggleMode),
            ("b", 11, .toggleSidebar),
            (",", 43, .openSettings),
        ]
        let extraFlags: [NSEvent.ModifierFlags] = [[], [.capsLock], [.function], [.numericPad], [.capsLock, .function]]

        for (character, keyCode, expected) in cases {
            for extra in extraFlags {
                let input = commandKey(character, keyCode: keyCode, modifiers: NSEvent.ModifierFlags.command.union(extra))
                #expect(PanelKeyResolver.action(for: input) == expected, "⌘\(character) + \(extra)")
                for mode in DraftMode.allCases {
                    #expect(PanelKeyResolver.action(for: input, mode: mode) == expected, "\(mode) ⌘\(character) + \(extra)")
                }
            }
        }
    }

    @Test("AC-9: ⌘ だけでない修飾キーの k・s・n・e・b・, や、⌘ の無い k・s・n・e・b・, は操作にならず、入力欄に渡す")
    func otherModifiersOnLetterKeysPassThrough() {
        let modifierSets: [NSEvent.ModifierFlags] = [[], [.shift], [.option], [.control], [.command, .shift], [.command, .option], [.command, .control]]

        for character in ["k", "s", "n", "e", "b", ","] {
            for modifiers in modifierSets {
                if character == "s", modifiers == [.command, .shift] { continue }
                let input = commandKey(character, keyCode: 0, modifiers: modifiers)
                #expect(PanelKeyResolver.action(for: input) == .passThrough, "\(modifiers) + \(character)")
            }
        }
        let commandJ = commandKey("j", keyCode: 38)
        #expect(PanelKeyResolver.action(for: commandJ) == .passThrough)
    }

    @Test("AC-9: 未確定の文字があるときの ⌘K・⌘S・⌘N・⌘E・⌘B・⌘, は入力メソッドに渡す。モードによらない")
    func panelCommandKeysPassThroughWhileComposing() {
        let keys = [("k", UInt16(40)), ("s", UInt16(1)), ("n", UInt16(45)), ("e", UInt16(14)), ("b", UInt16(11)), (",", UInt16(43))]
        for (character, keyCode) in keys {
            let input = commandKey(character, keyCode: keyCode, hasMarkedText: true)
            #expect(PanelKeyResolver.action(for: input) == .passThrough, "⌘\(character)")
            for mode in DraftMode.allCases {
                #expect(PanelKeyResolver.action(for: input, mode: mode) == .passThrough, "\(mode) ⌘\(character)")
            }
        }
    }

    @Test("AC-1: ⇧⌘S はファイルへの書き出しの操作になり、Caps Lock・fn・テンキーの印が付いていても、どのモードでも同じ")
    func shiftCommandSExportsToFile() {
        let extraFlags: [NSEvent.ModifierFlags] = [[], [.capsLock], [.function], [.numericPad], [.capsLock, .function]]
        for extra in extraFlags {
            let input = commandKey("s", keyCode: 1, modifiers: NSEvent.ModifierFlags([.command, .shift]).union(extra))
            for mode in DraftMode.allCases {
                #expect(PanelKeyResolver.action(for: input, mode: mode) == .exportToFile, "\(mode) + \(extra)")
            }
        }
    }

    @Test("AC-1: ⇧⌘S が確定キーに残っていても書き出しが勝つ。⇧⌘K・⇧⌘E・⌥⌘S・⌃⌘S・⇧S・⇧⌥⌘S は書き出しにならない")
    func exportKeyIsExactAndWinsOverCommitKey() {
        let shiftCommandS = PanelShortcut(keyCode: 1, modifiers: [.command, .shift])
        let input = commandKey("s", keyCode: 1, modifiers: [.command, .shift])
        #expect(PanelKeyResolver.action(for: input, commitKey: shiftCommandS, commitAndSendKey: nil) == .exportToFile)

        let others: [(String, NSEvent.ModifierFlags)] = [
            ("k", [.command, .shift]),
            ("e", [.command, .shift]),
            ("s", [.command, .option]),
            ("s", [.command, .control]),
            ("s", [.shift]),
            ("s", [.command, .shift, .option]),
        ]
        for (character, modifiers) in others {
            #expect(
                PanelKeyResolver.action(for: commandKey(character, keyCode: 0, modifiers: modifiers)) == .passThrough,
                "\(modifiers) + \(character)"
            )
        }
    }

    @Test("AC-2: 未確定の文字があるときの ⇧⌘S は入力メソッドに渡す。モードによらない")
    func shiftCommandSPassesThroughWhileComposing() {
        let input = commandKey("s", keyCode: 1, modifiers: [.command, .shift], hasMarkedText: true)
        for mode in DraftMode.allCases {
            #expect(PanelKeyResolver.action(for: input, mode: mode) == .passThrough, "\(mode)")
        }
    }

    @Test("AC-21: esc・確定キー・確定+送信キーの判定は ⌘K・⌘S・⌘N を足しても変わらない")
    func existingKeysAreUnchanged() {
        let escape = PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false)
        let commandReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
        let commandShiftReturn = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)

        #expect(PanelKeyResolver.action(for: escape) == .cancel)
        #expect(PanelKeyResolver.action(for: commandShiftReturn) == .commit)
        #expect(PanelKeyResolver.action(for: commandReturn) == .commitAndSend)
        #expect(PanelKeyResolver.action(for: commandReturn, commitKey: nil, commitAndSendKey: nil) == .passThrough)
    }

    // MARK: - 割り当てていない ⌘ つきの Enter の改行

    @Test("AC-11: ⌘Enter・⌘⇧Enter は入力欄が自分で改行を入れる対象になり、修飾なし・Shift だけ・⌥ や ⌃ を含むもの・変換中・Enter 以外のキーは対象にならない")
    func explicitNewlineOnlyForCommandEnter() {
        let insertsNewline: [(NSEvent.ModifierFlags, String)] = [
            ([.command], "⌘"),
            ([.command, .shift], "⇧⌘"),
            ([.command, .capsLock], "⌘ + Caps Lock"),
            ([.command, .shift, .function], "⇧⌘ + fn"),
            ([.command, .numericPad], "⌘ + テンキーの印"),
        ]
        let leavesToTextView: [(NSEvent.ModifierFlags, String)] = [
            ([], "修飾なし"),
            ([.shift], "⇧"),
            ([.shift, .capsLock], "⇧ + Caps Lock"),
            ([.command, .option], "⌥⌘"),
            ([.command, .control], "⌃⌘"),
            ([.command, .shift, .option], "⌥⇧⌘"),
            ([.option], "⌥"),
            ([.control], "⌃"),
        ]

        for keyCode in [KeyCode.returnKey, KeyCode.keypadEnter] {
            for (modifiers, label) in insertsNewline {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input) == true, "\(label) + keyCode \(keyCode)")
            }
            for (modifiers, label) in leavesToTextView {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input) == false, "\(label) + keyCode \(keyCode)")
            }
            for modifiers: NSEvent.ModifierFlags in [[.command], [.command, .shift]] {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: true)
                #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input) == false, "変換中 \(modifiers) + keyCode \(keyCode)")
            }
        }

        for keyCode in [KeyCode.escape, UInt16(0)] {
            for modifiers: NSEvent.ModifierFlags in [[.command], [.command, .shift]] {
                let input = PanelKeyInput(keyCode: keyCode, modifiers: modifiers, hasMarkedText: false)
                #expect(PanelKeyResolver.insertsNewlineExplicitly(for: input) == false, "keyCode \(keyCode) + \(modifiers)")
            }
        }
    }
}
