import AppKit

enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
}

/// @note p0-329
struct PanelKeyInput: Equatable {
    var keyCode: UInt16
    /// @note p0-330
    var modifiers: NSEvent.ModifierFlags
    /// @note p0-331
    var hasMarkedText: Bool
    /// @note p0-332
    var characters: String = ""
}

enum PanelKeyAction: Equatable {
    /// @note p0-333
    case cancel
    /// @note p0-334
    case passThrough
    /// @note p0-335
    case commit
    /// @note p0-336
    case commitAndSend
}

enum PanelKeyResolver {
    static func action(
        for input: PanelKeyInput,
        commitKey: PanelShortcut? = PanelShortcut.defaultCommitKey,
        commitAndSendKey: PanelShortcut? = PanelShortcut.defaultCommitAndSendKey
    ) -> PanelKeyAction {
        // @note p0-337
        if input.hasMarkedText {
            return .passThrough
        }
        if input.keyCode == KeyCode.escape {
            return .cancel
        }
        // @note p0-338
        if let commitKey, commitKey.matches(input) {
            return .commit
        }
        if let commitAndSendKey, commitAndSendKey.matches(input) {
            return .commitAndSend
        }
        // @note p0-339
        return .passThrough
    }

    /// @note p0-340
    static func insertsNewlineExplicitly(for input: PanelKeyInput) -> Bool {
        guard !input.hasMarkedText,
              input.keyCode == KeyCode.returnKey || input.keyCode == KeyCode.keypadEnter else {
            return false
        }
        let modifiers = input.modifiers.intersection([.shift, .control, .option, .command])
        return modifiers == [.command] || modifiers == [.command, .shift]
    }
}
