import AppKit

enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
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
}

/// 下書きの削除の確認を出している間のキーの意味。
enum DeletionConfirmationKey: Equatable {
    case delete
    case cancel
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

    /// 保存していない文章の切り替えの確認を出している間のキーが選ぶ操作。当てはまらなければ `nil`。
    static func confirmationChoice(for input: PanelKeyInput) -> UnsavedTextChoice? {
        guard !input.hasMarkedText else { return nil }
        let modifiers = input.modifiers.intersection(PanelShortcut.relevantModifiers)
        if modifiers.isEmpty {
            if isReturn(input) { return .save }
            if input.keyCode == KeyCode.escape { return .cancel }
        }
        if modifiers == [.command], input.characters == "d" {
            return .discard
        }
        return nil
    }

    /// 下書きの削除の確認を出している間のキーが選ぶ操作。当てはまらなければ `nil`。
    static func deletionConfirmationKey(for input: PanelKeyInput) -> DeletionConfirmationKey? {
        guard !input.hasMarkedText,
              input.modifiers.intersection(PanelShortcut.relevantModifiers).isEmpty else { return nil }
        if isReturn(input) { return .delete }
        if input.keyCode == KeyCode.escape { return .cancel }
        return nil
    }

    private static func panelCommandAction(for input: PanelKeyInput) -> PanelKeyAction? {
        guard input.modifiers.intersection(PanelShortcut.relevantModifiers) == [.command] else { return nil }
        switch input.characters {
        case "k": return .openSearch
        case "s": return .saveDraft
        case "n": return .newDraft
        default: return nil
        }
    }

    private static func isReturn(_ input: PanelKeyInput) -> Bool {
        input.keyCode == KeyCode.returnKey || input.keyCode == KeyCode.keypadEnter
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
