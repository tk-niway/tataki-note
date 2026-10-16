import AppKit

enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
}

/// 入力欄に届いたキーの値。
struct PanelKeyInput: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var hasMarkedText: Bool
    var characters: String = ""
}

enum PanelKeyAction: Equatable {
    case cancel
    case passThrough
    case commit
    case commitAndSend
    case openSearch
    case saveDraft
    case newDraft
    case toggleSidebar
    case openSettings
}

enum PanelKeyResolver {
    static func action(
        for input: PanelKeyInput,
        commitKey: PanelShortcut? = PanelShortcut.defaultCommitKey,
        commitAndSendKey: PanelShortcut? = PanelShortcut.defaultCommitAndSendKey
    ) -> PanelKeyAction {
        if input.hasMarkedText {
            return .passThrough
        }
        if input.keyCode == KeyCode.escape {
            return .cancel
        }
        if let action = panelCommandAction(for: input) {
            return action
        }
        if let commitKey, commitKey.matches(input) {
            return .commit
        }
        if let commitAndSendKey, commitAndSendKey.matches(input) {
            return .commitAndSend
        }
        return .passThrough
    }

    /// 入力欄の外(一覧・検索欄)で押されたキーに対する確定の操作。確定・確定+送信でなければ `nil`。
    static func actionOutsideEditor(
        for input: PanelKeyInput,
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?
    ) -> PanelKeyAction? {
        guard !input.hasMarkedText else { return nil }
        let resolved = action(for: input, commitKey: commitKey, commitAndSendKey: commitAndSendKey)
        switch resolved {
        case .commit, .commitAndSend: return resolved
        default: return nil
        }
    }

    private static func panelCommandAction(for input: PanelKeyInput) -> PanelKeyAction? {
        guard input.modifiers.intersection(PanelShortcut.relevantModifiers) == [.command] else { return nil }
        switch input.characters {
        case "k": return .openSearch
        case "s": return .saveDraft
        case "n": return .newDraft
        case "b": return .toggleSidebar
        case ",": return .openSettings
        default: return nil
        }
    }

    static func insertsNewlineExplicitly(for input: PanelKeyInput) -> Bool {
        guard !input.hasMarkedText,
              input.keyCode == KeyCode.returnKey || input.keyCode == KeyCode.keypadEnter else {
            return false
        }
        let modifiers = input.modifiers.intersection([.shift, .control, .option, .command])
        return modifiers == [.command] || modifiers == [.command, .shift]
    }
}
