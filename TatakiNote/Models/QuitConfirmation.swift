import AppKit

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

/// ⌘Q の判定。
enum QuitConfirmation {
    /// 修飾キーが ⌘ だけで、文字が Q のとき true。
    static func isQuitKey(modifiers: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        modifiers.intersection(PanelShortcut.relevantModifiers) == [.command]
            && charactersIgnoringModifiers?.lowercased() == "q"
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
}
