import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct ReservedPanelKeysTests {
    private let commandK = PanelShortcut(keyCode: 40, modifiers: [.command])
    private let commandS = PanelShortcut(keyCode: 1, modifiers: [.command])
    private let commandN = PanelShortcut(keyCode: 45, modifiers: [.command])
    private let commandE = PanelShortcut(keyCode: 14, modifiers: [.command])
    private let commandB = PanelShortcut(keyCode: 11, modifiers: [.command])
    private let commandComma = PanelShortcut(keyCode: 43, modifiers: [.command])
    private let commandJ = PanelShortcut(keyCode: 38, modifiers: [.command])
    private let defaultHotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
    private let defaultCommit = PanelShortcut.commandShiftReturn
    private let defaultCommitAndSend = PanelShortcut.commandReturn

    private func isReservedByKeyCode(_ shortcut: PanelShortcut) -> Bool {
        shortcut.modifiers == [.command] && [40, 1, 45, 14, 11, 43].contains(shortcut.keyCode)
    }

    private func migrate(
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?,
        hotkey: PanelShortcut?
    ) -> ReservedPanelKeys.Migration {
        ReservedPanelKeys.migrate(
            commitKey: commitKey,
            commitAndSendKey: commitAndSendKey,
            hotkey: hotkey,
            defaultHotkey: defaultHotkey,
            isReserved: isReservedByKeyCode
        )
    }

    @Test("AC-10: 記録のキーは、修飾キーが ⌘ だけで文字が k・s・n・e・b・, のときだけ予約に当たる")
    func candidateIsReservedOnlyForCommandKSN() {
        for (keyCode, characters) in [(40, "k"), (1, "s"), (45, "n"), (14, "e"), (11, "b"), (43, ",")] as [(UInt16, String)] {
            let candidate = PanelShortcutCandidate(
                shortcut: PanelShortcut(keyCode: keyCode, modifiers: [.command]),
                characters: characters
            )
            #expect(ReservedPanelKeys.isReserved(candidate), "⌘\(characters)")
        }

        let notReserved: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (40, [.command, .shift], "k"), (1, [.command, .option], "s"), (45, [.command, .control], "n"),
            (14, [.command, .shift], "e"), (14, [.command, .option], "e"), (14, [.option], "e"),
            (40, [.option], "k"), (38, [.command], "j"), (12, [.command], "q"),
        ]
        for (keyCode, modifiers, characters) in notReserved {
            let candidate = PanelShortcutCandidate(
                shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers),
                characters: characters
            )
            #expect(!ReservedPanelKeys.isReserved(candidate), "\(modifiers) \(characters)")
        }
    }

    @Test("AC-11: 保存値の ⌘K・⌘S・⌘N・⌘E・⌘B・⌘, は今のキー配列の表示で予約に当たり、⇧⌘K・⇧⌘E・⌘J は当たらない")
    func storedShortcutIsReservedByDisplayText() {
        #expect(ReservedPanelKeys.isReserved(commandK))
        #expect(ReservedPanelKeys.isReserved(commandS))
        #expect(ReservedPanelKeys.isReserved(commandN))
        #expect(ReservedPanelKeys.isReserved(commandE))
        #expect(ReservedPanelKeys.isReserved(commandB))
        #expect(ReservedPanelKeys.isReserved(commandComma))
        #expect(!ReservedPanelKeys.isReserved(PanelShortcut(keyCode: 40, modifiers: [.command, .shift])))
        #expect(!ReservedPanelKeys.isReserved(PanelShortcut(keyCode: 14, modifiers: [.command, .shift])))
        #expect(!ReservedPanelKeys.isReserved(commandJ))
        #expect(!ReservedPanelKeys.isReserved(PanelShortcut.commandReturn))
    }

    @Test("AC-11: 確定+挿入キー・確定+送信キーが ⌘E なら、それぞれの初期値に戻る(実際の予約の判定で)")
    func commandECommitKeysAreResetToTheirDefaults() {
        let both = ReservedPanelKeys.migrate(
            commitKey: commandE,
            commitAndSendKey: commandE,
            hotkey: defaultHotkey,
            defaultHotkey: defaultHotkey
        )
        #expect(both == .init(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))

        let onlySend = ReservedPanelKeys.migrate(
            commitKey: commandJ,
            commitAndSendKey: commandE,
            hotkey: nil,
            defaultHotkey: defaultHotkey
        )
        #expect(onlySend == .init(commitKey: commandJ, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))
    }

    @Test("AC-11: ホットキーが ⌘E なら初期値に戻す(実際の予約の判定で)")
    func commandEHotkeyIsReset() {
        let result = ReservedPanelKeys.migrate(
            commitKey: nil,
            commitAndSendKey: nil,
            hotkey: commandE,
            defaultHotkey: defaultHotkey
        )
        #expect(result.shouldResetHotkey)
    }

    @Test("AC-8: 確定+挿入キー・確定+送信キーが予約のキーなら、それぞれの初期値に戻る")
    func reservedCommitKeysAreResetToTheirDefaults() {
        let both = migrate(commitKey: commandS, commitAndSendKey: commandN, hotkey: defaultHotkey)
        #expect(both == .init(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))

        let onlyCommit = migrate(commitKey: commandK, commitAndSendKey: commandJ, hotkey: nil)
        #expect(onlyCommit == .init(commitKey: defaultCommit, commitAndSendKey: commandJ, shouldResetHotkey: false))

        let onlySend = migrate(commitKey: commandJ, commitAndSendKey: commandS, hotkey: nil)
        #expect(onlySend == .init(commitKey: commandJ, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))
    }

    @Test("AC-8: 予約のキーでない確定キーと登録なしは変わらない")
    func unreservedAndMissingKeysAreKept() {
        let custom = migrate(commitKey: commandJ, commitAndSendKey: PanelShortcut.shiftReturn, hotkey: defaultHotkey)
        #expect(custom == .init(commitKey: commandJ, commitAndSendKey: PanelShortcut.shiftReturn, shouldResetHotkey: false))

        let missing = migrate(commitKey: nil, commitAndSendKey: nil, hotkey: nil)
        #expect(missing == .init(commitKey: nil, commitAndSendKey: nil, shouldResetHotkey: false))

        let defaults = migrate(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, hotkey: defaultHotkey)
        #expect(defaults == .init(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))
    }

    @Test("AC-8: 戻した結果もう一方の確定キーと同じになるなら、両方を初期値に戻す")
    func collisionBetweenCommitKeysResetsBoth() {
        let sendIsCommitDefault = migrate(commitKey: commandS, commitAndSendKey: defaultCommit, hotkey: nil)
        #expect(sendIsCommitDefault == .init(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))

        let commitIsSendDefault = migrate(commitKey: defaultCommitAndSend, commitAndSendKey: commandN, hotkey: nil)
        #expect(commitIsSendDefault == .init(commitKey: defaultCommit, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))
    }

    @Test("AC-8: 戻した確定キーが(戻した後の)ホットキーと同じになるなら、その確定キーは登録なしになる")
    func resetCommitKeyCollidingWithHotkeyBecomesUnregistered() {
        let commitCollides = migrate(commitKey: commandS, commitAndSendKey: defaultCommitAndSend, hotkey: defaultCommit)
        #expect(commitCollides == .init(commitKey: nil, commitAndSendKey: defaultCommitAndSend, shouldResetHotkey: false))

        let sendCollides = migrate(commitKey: defaultCommit, commitAndSendKey: commandN, hotkey: defaultCommitAndSend)
        #expect(sendCollides == .init(commitKey: defaultCommit, commitAndSendKey: nil, shouldResetHotkey: false))
    }

    @Test("AC-8, AC-9: ホットキーが予約のキーで初期値に戻るとき、戻した後のホットキーと同じ確定キーは初期値に戻る")
    func commitKeyEqualToResetHotkeyIsReset() {
        let result = migrate(commitKey: defaultHotkey, commitAndSendKey: commandJ, hotkey: commandK)
        #expect(result == .init(commitKey: defaultCommit, commitAndSendKey: commandJ, shouldResetHotkey: true))

        let notReset = migrate(commitKey: defaultHotkey, commitAndSendKey: commandJ, hotkey: commandJ)
        #expect(notReset == .init(commitKey: defaultHotkey, commitAndSendKey: commandJ, shouldResetHotkey: false))
    }

    @Test("AC-11: ホットキーが ⌘K・⌘S・⌘N・⌘E・⌘B・⌘, なら初期値に戻し、それ以外のキー・登録なしはそのまま")
    func reservedHotkeyIsReset() {
        for key in [commandK, commandS, commandN, commandE, commandB, commandComma] {
            #expect(migrate(commitKey: nil, commitAndSendKey: nil, hotkey: key).shouldResetHotkey)
        }
        for key in [commandJ, defaultHotkey, PanelShortcut(keyCode: 40, modifiers: [.command, .shift])] {
            #expect(!migrate(commitKey: nil, commitAndSendKey: nil, hotkey: key).shouldResetHotkey)
        }
        #expect(!migrate(commitKey: nil, commitAndSendKey: nil, hotkey: nil).shouldResetHotkey)
    }

    @Test("AC-8, AC-9: apply は変わるときだけ設定に入れて保存し、ホットキーを戻すときだけ resetHotkey を呼ぶ")
    func applyWritesSettingsAndResetsHotkey() throws {
        let temp = try TemporaryDefaults()
        defer { temp.defaults.removePersistentDomain(forName: temp.name) }
        let settings = temp.makeSettings()
        settings.commitKey = commandS
        settings.commitAndSendKey = commandN

        var resetCount = 0
        ReservedPanelKeys.apply(to: settings, hotkey: commandK, defaultHotkey: defaultHotkey) { resetCount += 1 }

        #expect(settings.commitKey == defaultCommit)
        #expect(settings.commitAndSendKey == defaultCommitAndSend)
        #expect(resetCount == 1)
        let reloaded = AppSettings(store: SettingsStore(defaults: temp.defaults))
        #expect(reloaded.commitKey == defaultCommit)
        #expect(reloaded.commitAndSendKey == defaultCommitAndSend)
    }

    @Test("AC-8, AC-9: apply は予約のキーが無ければ何も変えず、resetHotkey も呼ばない(2回目も同じ)")
    func applyLeavesUnreservedKeysAlone() throws {
        let temp = try TemporaryDefaults()
        defer { temp.defaults.removePersistentDomain(forName: temp.name) }
        let settings = temp.makeSettings()
        settings.commitKey = commandJ
        settings.commitAndSendKey = nil

        var resetCount = 0
        for _ in 0..<2 {
            ReservedPanelKeys.apply(to: settings, hotkey: defaultHotkey, defaultHotkey: defaultHotkey) { resetCount += 1 }
        }

        #expect(settings.commitKey == commandJ)
        #expect(settings.commitAndSendKey == nil)
        #expect(resetCount == 0)
    }
}
