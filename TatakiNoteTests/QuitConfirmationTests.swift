import AppKit
import Carbon.HIToolbox
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

    private static let keyCodeW: UInt16 = 13
    private static let keyCodeH: UInt16 = 4

    private func isQuitKey(
        _ modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16 = QuitConfirmationTests.keyCodeQ,
        characters: String? = "q"
    ) -> Bool {
        QuitConfirmation.isQuitKey(keyCode: keyCode, modifiers: modifiers, charactersIgnoringModifiers: characters)
    }

    private func keyEvent(
        type: NSEvent.EventType = .keyDown,
        modifiers: NSEvent.ModifierFlags = .command,
        keyCode: UInt16 = QuitConfirmationTests.keyCodeQ,
        characters: String = "q"
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test("AC-14: ⌘Q は終了のキー(大文字でも)")
    func commandQIsQuitKey() {
        #expect(isQuitKey(.command, characters: "q"))
        #expect(isQuitKey(.command, characters: "Q"))
    }

    @Test("AC-29: Q のキーコードに ⌘ だけを付けたら、文字が「q」「Q」「た」・空・無しのどれでも ⌘Q")
    func commandQAtQPositionIsQuitKeyWhateverTheCharacter() {
        for characters in ["q", "Q", "た", "", nil] as [String?] {
            #expect(isQuitKey(.command, characters: characters), "\(characters ?? "nil")")
        }
    }

    @Test("AC-29: 英字の文字が来たときはその文字で決める(AZERTY の「a」・Dvorak の「'」は ⌘Q ではなく、Dvorak の「q」は ⌘Q)")
    func asciiCharacterDecidesBeforeKeyCode() {
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeQ, characters: "a"))
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeQ, characters: "'"))
        #expect(isQuitKey(.command, keyCode: 7, characters: "q"))
    }

    @Test("AC-29: かな入力の他のキー(「ち」など)や Q 以外のキーコードは ⌘Q ではない")
    func otherKanaKeysAreNotQuitKey() {
        #expect(!isQuitKey(.command, keyCode: 0, characters: "ち"))
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeW, characters: "w"))
    }

    @Test("AC-29: キーの押下の ⌘Q のイベントだけを ⌘Q とみなす(クリック・キーを離したとき・イベント無しは違う)")
    func quitKeyEventIsKeyDownOnly() throws {
        let commandQ = try keyEvent()
        let commandQOnKana = try keyEvent(characters: "た")
        let shiftCommandQ = try keyEvent(modifiers: [.command, .shift])
        let keyUp = try keyEvent(type: .keyUp)
        #expect(QuitConfirmation.isQuitKeyEvent(commandQ))
        #expect(QuitConfirmation.isQuitKeyEvent(commandQOnKana))
        #expect(!QuitConfirmation.isQuitKeyEvent(shiftCommandQ))
        #expect(!QuitConfirmation.isQuitKeyEvent(keyUp))
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        #expect(!QuitConfirmation.isQuitKeyEvent(click))
        #expect(!QuitConfirmation.isQuitKeyEvent(nil))
    }

    @Test("AC-14: Caps Lock・fn が付いていても ⌘Q は終了のキー")
    func capsLockAndFunctionAreIgnored() {
        #expect(isQuitKey([.command, .capsLock]))
        #expect(isQuitKey([.command, .function]))
        #expect(isQuitKey([.command, .numericPad]))
    }

    @Test("AC-14: ⇧⌘Q・⌥⌘Q・⌃⌘Q は終了のキーではない")
    func otherModifiersAreNotQuitKey() {
        #expect(!isQuitKey([.command, .shift]))
        #expect(!isQuitKey([.command, .option]))
        #expect(!isQuitKey([.command, .control]))
        #expect(!isQuitKey([.command, .shift, .option, .control]))
        #expect(!isQuitKey([.command, .shift], characters: "た"))
    }

    @Test("AC-14: 修飾なしの q・⌘ の付かない q は終了のキーではない")
    func missingCommandIsNotQuitKey() {
        #expect(!isQuitKey([]))
        #expect(!isQuitKey(.shift))
        #expect(!isQuitKey(.option))
        #expect(!isQuitKey(.control))
    }

    @Test("AC-14: ⌘W など Q 以外のキーは終了のキーではない")
    func otherKeysAreNotQuitKey() {
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeW, characters: "w"))
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeH, characters: "h"))
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeW, characters: ""))
        #expect(!isQuitKey(.command, keyCode: Self.keyCodeW, characters: nil))
    }

    // MARK: - isQuitAppleEvent

    @Test("AC-30: 終了の Apple Event だけが終了の頼みの Apple Event")
    func quitAppleEventIsDetected() {
        #expect(QuitConfirmation.isQuitAppleEvent(eventID: AEEventID(kAEQuitApplication)))
        #expect(!QuitConfirmation.isQuitAppleEvent(eventID: AEEventID(kAEOpenApplication)))
        #expect(!QuitConfirmation.isQuitAppleEvent(eventID: nil))
    }

    // MARK: - terminationReply

    private func reply(
        isQuitKeyEvent: Bool = true,
        isQuitAppleEvent: Bool = false,
        isRecordingShortcut: Bool = false,
        isPanelCommitKey: Bool = false,
        isModalRunning: Bool = false,
        isConfirming: Bool = false,
        confirmsQuit: Bool = true
    ) -> QuitTerminationReply {
        QuitConfirmation.terminationReply(
            isQuitKeyEvent: isQuitKeyEvent,
            isQuitAppleEvent: isQuitAppleEvent,
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning,
            isConfirming: isConfirming,
            confirmsQuit: confirmsQuit
        )
    }

    @Test("AC-30: 終了の頼みのときのイベントが ⌘Q で、確認がオンなら終了をやめて確かめる。オフなら終了する")
    func quitKeyEventConfirmsOrTerminates() {
        #expect(reply(confirmsQuit: true) == .cancelAndConfirm)
        #expect(reply(confirmsQuit: false) == .terminate)
    }

    @Test("AC-30: ⌘Q でないイベント(クリック・↩・イベントなし)の終了の頼みは、確かめ中でも終了する")
    func nonQuitKeyEventTerminates() {
        #expect(reply(isQuitKeyEvent: false) == .terminate)
        #expect(reply(isQuitKeyEvent: false, isConfirming: true) == .terminate)
        #expect(reply(isQuitKeyEvent: false, isModalRunning: true) == .terminate)
    }

    @Test("AC-30: 終了の Apple Event(Dock のメニュー・ログアウト)なら、前の ⌘Q のイベントが残っていても終了する")
    func quitAppleEventTerminates() {
        #expect(reply(isQuitAppleEvent: true) == .terminate)
        #expect(reply(isQuitAppleEvent: true, isConfirming: true) == .terminate)
        #expect(reply(isQuitAppleEvent: true, isModalRunning: true) == .terminate)
    }

    @Test("AC-30: 確かめ中・モーダル中・記録中・パネルの確定キーの ⌘Q は、終了をやめるだけで確かめない")
    func guardedQuitKeyCancels() {
        #expect(reply(isConfirming: true) == .cancel)
        #expect(reply(isConfirming: true, confirmsQuit: false) == .cancel)
        #expect(reply(isModalRunning: true) == .cancel)
        #expect(reply(isModalRunning: true, confirmsQuit: false) == .cancel)
        #expect(reply(isRecordingShortcut: true) == .cancel)
        #expect(reply(isPanelCommitKey: true) == .cancel)
        #expect(reply(isPanelCommitKey: true, confirmsQuit: false) == .cancel)
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
