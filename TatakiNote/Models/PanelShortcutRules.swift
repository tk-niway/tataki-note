import AppKit

enum PanelShortcutRole: CaseIterable {
    case commit
    case commitAndSend
}

/// 記録ボックスで押されたキー。
struct PanelShortcutCandidate: Equatable {
    let shortcut: PanelShortcut
    let characters: String
}

enum PanelShortcutRejection: Equatable {
    case missingModifier
    case reservedForClosing
    case reservedForEditing
    case usedByHotkey
    case usedByOtherRole(PanelShortcutRole)

    func message(for shortcut: PanelShortcut) -> String {
        let key = shortcut.displayText
        switch self {
        case .missingModifier:
            return String(localized: "⌘・⌥・⌃・⇧ のどれかと組み合わせたキーを押してください。")
        case .reservedForClosing:
            return String(localized: "esc はパネルを閉じるキーのため、修飾キーと組み合わせても登録できません。")
        case .reservedForEditing:
            return String(localized: "\(key) は入力欄の編集ショートカットで使っているため、登録できません。")
        case .usedByHotkey:
            return String(localized: "\(key) は「パネルを開く・閉じる」で使っているため、登録できません。")
        case .usedByOtherRole(.commitAndSend):
            return String(localized: "\(key) は「確定+送信キー」で使っているため、登録できません。")
        case .usedByOtherRole(.commit):
            return String(localized: "\(key) は「確定キー」で使っているため、登録できません。")
        }
    }
}

enum PanelShortcutRules {
    private static let editingCharacters: Set<String> = ["a", "c", "d", "h", "l", "v", "x", "z"]

    static func rejection(
        for candidate: PanelShortcutCandidate,
        role: PanelShortcutRole,
        hotkey: PanelShortcut?,
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?
    ) -> PanelShortcutRejection? {
        let shortcut = candidate.shortcut

        if !shortcut.hasModifier {
            return .missingModifier
        }
        if shortcut.keyCode == KeyCode.escape {
            return .reservedForClosing
        }
        if isReservedForEditing(candidate) {
            return .reservedForEditing
        }
        if let hotkey, shortcut == hotkey {
            return .usedByHotkey
        }
        switch role {
        case .commit:
            if let commitAndSendKey, shortcut == commitAndSendKey {
                return .usedByOtherRole(.commitAndSend)
            }
        case .commitAndSend:
            if let commitKey, shortcut == commitKey {
                return .usedByOtherRole(.commit)
            }
        }
        return nil
    }

    private static func isReservedForEditing(_ candidate: PanelShortcutCandidate) -> Bool {
        let shortcut = candidate.shortcut
        if shortcut.modifiers == [.command], editingCharacters.contains(candidate.characters) {
            return true
        }
        if shortcut.modifiers == [.command, .shift], candidate.characters == "z" {
            return true
        }
        let input = PanelKeyInput(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, hasMarkedText: false)
        return LineEditing.arrowCommand(for: input) != nil
    }
}
