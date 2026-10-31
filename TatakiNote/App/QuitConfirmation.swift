import AppKit
import Carbon.HIToolbox

/// ⌘Q が押されたときにすること。
nonisolated enum QuitKeyAction: Equatable, Sendable {
    /// イベントをそのまま流す。
    case passThrough
    /// イベントを捨てる。
    case ignore
    /// すぐ終了する。
    case quit
    /// 確かめの窓を出す。
    case confirm
}

/// 終了の頼みへの返事。
nonisolated enum QuitTerminationReply: Equatable, Sendable {
    /// そのまま終了する。
    case terminate
    /// 終了をやめる。
    case cancel
    /// 終了をやめて、確かめの窓を出す。
    case cancelAndConfirm
}

/// ⌘Q の判定。
enum QuitConfirmation {
    private static let quitKeyCode: UInt16 = 12

    /// 修飾キーが ⌘ だけで、押したキーが Q のとき true。入力ソースによらない。
    static func isQuitKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        guard modifiers.intersection(PanelShortcut.relevantModifiers) == [.command] else { return false }
        if let character = asciiCharacter(charactersIgnoringModifiers) {
            return character == "q"
        }
        return keyCode == quitKeyCode
    }

    /// キーを押したイベントで、⌘Q のとき true。イベントが無い・キーの押下でないときは false。
    static func isQuitKeyEvent(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return isQuitKey(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    /// 処理中の Apple Event が終了の頼み(Dock のメニュー・ログアウトなど)のとき true。
    static func isQuitAppleEvent(eventID: AEEventID?) -> Bool {
        eventID == AEEventID(kAEQuitApplication)
    }

    private static func asciiCharacter(_ characters: String?) -> Character? {
        guard let characters = characters?.lowercased(), characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              scalar.value > 0x20, scalar.value <= 0x7E
        else { return nil }
        return Character(scalar)
    }

    /// パネルがキーで、押したキーが確定キーか確定+送信キーのとき true。
    static func isPanelCommitKey(_ input: PanelKeyInput, isPanelKey: Bool, commitKey: PanelShortcut?, commitAndSendKey: PanelShortcut?) -> Bool {
        guard isPanelKey else { return false }
        return commitKey?.matches(input) == true || commitAndSendKey?.matches(input) == true
    }

    /// ⌘Q のときにすることを決める。
    static func action(
        isQuitKey: Bool,
        isRecordingShortcut: Bool,
        isPanelCommitKey: Bool,
        isModalRunning: Bool,
        isConfirming: Bool,
        confirmsQuit: Bool
    ) -> QuitKeyAction {
        guard isQuitKey else { return .passThrough }
        if isRecordingShortcut || isPanelCommitKey { return .passThrough }
        if isModalRunning || isConfirming { return .ignore }
        return confirmsQuit ? .confirm : .quit
    }

    /// 終了の頼みが来たときの返事を決める。
    static func terminationReply(
        isQuitKeyEvent: Bool,
        isQuitAppleEvent: Bool,
        isRecordingShortcut: Bool,
        isPanelCommitKey: Bool,
        isModalRunning: Bool,
        isConfirming: Bool,
        confirmsQuit: Bool
    ) -> QuitTerminationReply {
        guard isQuitKeyEvent, !isQuitAppleEvent else { return .terminate }
        let keyAction = action(
            isQuitKey: true,
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning,
            isConfirming: isConfirming,
            confirmsQuit: confirmsQuit
        )
        switch keyAction {
        case .confirm:
            return .cancelAndConfirm
        case .quit:
            return .terminate
        case .ignore, .passThrough:
            return .cancel
        }
    }
}
