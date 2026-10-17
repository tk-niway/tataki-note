import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct QuitConfirmationTests {
    private static let keyCodeQ: UInt16 = 12

    private func input(modifiers: NSEvent.ModifierFlags = .command) -> PanelKeyInput {
        PanelKeyInput(keyCode: Self.keyCodeQ, modifiers: modifiers, hasMarkedText: false, characters: "q")
    }

    private func action(
        isQuitKey: Bool = true,
        isRecordingShortcut: Bool = false,
        isPanelCommitKey: Bool = false,
        isModalRunning: Bool = false,
        isConfirming: Bool = false,
        confirmsQuit: Bool = true
    ) -> QuitKeyAction {
        QuitConfirmation.action(
            isQuitKey: isQuitKey,
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning,
            isConfirming: isConfirming,
            confirmsQuit: confirmsQuit
        )
    }

    // MARK: - isQuitKey

    @Test("AC-14: ⌘Q は終了のキー(大文字でも)")
    func commandQIsQuitKey() {
        #expect(QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: "q"))
        #expect(QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: "Q"))
    }

    @Test("AC-14: Caps Lock・fn が付いていても ⌘Q は終了のキー")
    func capsLockAndFunctionAreIgnored() {
        #expect(QuitConfirmation.isQuitKey(modifiers: [.command, .capsLock], charactersIgnoringModifiers: "q"))
        #expect(QuitConfirmation.isQuitKey(modifiers: [.command, .function], charactersIgnoringModifiers: "q"))
        #expect(QuitConfirmation.isQuitKey(modifiers: [.command, .numericPad], charactersIgnoringModifiers: "q"))
    }

    @Test("AC-14: ⇧⌘Q・⌥⌘Q・⌃⌘Q は終了のキーではない")
    func otherModifiersAreNotQuitKey() {
        #expect(!QuitConfirmation.isQuitKey(modifiers: [.command, .shift], charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: [.command, .option], charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: [.command, .control], charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: [.command, .shift, .option, .control], charactersIgnoringModifiers: "q"))
    }

    @Test("AC-14: 修飾なしの q・⌘ の付かない q は終了のキーではない")
    func missingCommandIsNotQuitKey() {
        #expect(!QuitConfirmation.isQuitKey(modifiers: [], charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .shift, charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .option, charactersIgnoringModifiers: "q"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .control, charactersIgnoringModifiers: "q"))
    }

    @Test("AC-14: ⌘W など Q 以外の文字は終了のキーではない")
    func otherCharactersAreNotQuitKey() {
        #expect(!QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: "w"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: "h"))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: ""))
        #expect(!QuitConfirmation.isQuitKey(modifiers: .command, charactersIgnoringModifiers: nil))
    }

    // MARK: - isPanelCommitKey

    @Test("AC-15: パネルがキーで ⌘Q が確定キーなら、確定キーとみなす")
    func panelCommitKeyIsDetected() {
        let commitKey = PanelShortcut(keyCode: Self.keyCodeQ, modifiers: .command)
        #expect(QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: true, commitKey: commitKey, commitAndSendKey: nil
        ))
    }

    @Test("AC-15: パネルがキーで ⌘Q が確定+送信キーなら、確定キーとみなす")
    func panelCommitAndSendKeyIsDetected() {
        let commitAndSendKey = PanelShortcut(keyCode: Self.keyCodeQ, modifiers: .command)
        #expect(QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: true, commitKey: nil, commitAndSendKey: commitAndSendKey
        ))
    }

    @Test("AC-15: パネル以外の窓では、⌘Q が確定キーでも確定キーとみなさない")
    func nonPanelWindowIsNotCommitKey() {
        let commitKey = PanelShortcut(keyCode: Self.keyCodeQ, modifiers: .command)
        #expect(!QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: false, commitKey: commitKey, commitAndSendKey: commitKey
        ))
    }

    @Test("AC-15: ⌘Q が確定キーに登録されていなければ、確定キーとみなさない")
    func unregisteredKeyIsNotCommitKey() {
        #expect(!QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: true, commitKey: .commandShiftReturn, commitAndSendKey: .commandReturn
        ))
        #expect(!QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: true, commitKey: nil, commitAndSendKey: nil
        ))
    }

    @Test("AC-15: 修飾キーが違う登録(⇧⌘Q)は、⌘Q を確定キーとみなさない")
    func differentModifiersAreNotCommitKey() {
        let shiftCommandQ = PanelShortcut(keyCode: Self.keyCodeQ, modifiers: [.command, .shift])
        #expect(!QuitConfirmation.isPanelCommitKey(
            input(), isPanelKey: true, commitKey: shiftCommandQ, commitAndSendKey: shiftCommandQ
        ))
    }

    // MARK: - action

    @Test("AC-15: 終了のキーでなければ、そのまま流す")
    func nonQuitKeyPassesThrough() {
        #expect(action(isQuitKey: false) == .passThrough)
        #expect(action(isQuitKey: false, isModalRunning: true, isConfirming: true, confirmsQuit: false) == .passThrough)
    }

    @Test("AC-15: 設定がオンなら確かめの窓を出す")
    func confirmsWhenSettingIsOn() {
        #expect(action(confirmsQuit: true) == .confirm)
    }

    @Test("AC-15: 設定がオフならすぐ終了する")
    func quitsImmediatelyWhenSettingIsOff() {
        #expect(action(confirmsQuit: false) == .quit)
    }

    @Test("AC-15: 確かめ中の ⌘Q は捨てる(設定がオフでも)")
    func keyWhileConfirmingIsIgnored() {
        #expect(action(isConfirming: true, confirmsQuit: true) == .ignore)
        #expect(action(isConfirming: true, confirmsQuit: false) == .ignore)
    }

    @Test("AC-15: 記録欄が記録中なら素通しにする(確かめ中・モーダル中・設定オフでも)")
    func recordingShortcutPassesThrough() {
        #expect(action(isRecordingShortcut: true) == .passThrough)
        #expect(action(isRecordingShortcut: true, isConfirming: true) == .passThrough)
        #expect(action(isRecordingShortcut: true, isModalRunning: true) == .passThrough)
        #expect(action(isRecordingShortcut: true, confirmsQuit: false) == .passThrough)
    }

    @Test("AC-15: パネルで ⌘Q が確定キーなら素通しにする(設定がオフでも)")
    func panelCommitKeyPassesThrough() {
        #expect(action(isPanelCommitKey: true, confirmsQuit: true) == .passThrough)
        #expect(action(isPanelCommitKey: true, confirmsQuit: false) == .passThrough)
        #expect(action(isPanelCommitKey: true, isConfirming: true) == .passThrough)
    }

    @Test("AC-15: モーダルの間は、確かめも終了もせずキーを捨てる(設定がオンでもオフでも)")
    func modalRunningIgnoresKey() {
        #expect(action(isModalRunning: true, confirmsQuit: true) == .ignore)
        #expect(action(isModalRunning: true, confirmsQuit: false) == .ignore)
        #expect(action(isModalRunning: true, isConfirming: true) == .ignore)
    }

    @Test("AC-15: 判定の順は、素通し → 捨てる → 設定の順")
    func decisionOrderForAllCombinations() {
        for isRecording in [false, true] {
            for isCommitKey in [false, true] {
                for isModal in [false, true] {
                    for isConfirming in [false, true] {
                        for confirmsQuit in [false, true] {
                            let result = action(
                                isRecordingShortcut: isRecording,
                                isPanelCommitKey: isCommitKey,
                                isModalRunning: isModal,
                                isConfirming: isConfirming,
                                confirmsQuit: confirmsQuit
                            )
                            let expected: QuitKeyAction
                            if isRecording || isCommitKey {
                                expected = .passThrough
                            } else if isModal || isConfirming {
                                expected = .ignore
                            } else {
                                expected = confirmsQuit ? .confirm : .quit
                            }
                            #expect(result == expected)
                        }
                    }
                }
            }
        }
    }
}
