import AppKit

enum PanelShortcutRole: CaseIterable {
    case commit
    case commitAndSend
}

extension PanelShortcutRole {
    /// 出荷時に割り当てているキー。
    var initialKey: PanelShortcut? {
        switch self {
        case .commit: PanelShortcut.defaultCommitKey
        case .commitAndSend: PanelShortcut.defaultCommitAndSendKey
        }
    }

    /// 設定の「ホットキーとキー操作」で記録ボックスの下に出す説明文。
    var settingDescription: String {
        settingDescription(initialKey: initialKey)
    }

    /// 初期値を指定して作る、記録ボックスの下の説明文。
    func settingDescription(initialKey: PanelShortcut?) -> String {
        let initialKeyText = initialKey?.displayText ?? String(localized: "登録なし")
        switch self {
        case .commit:
            return String(localized: "書いた文章を元のアプリに挿入します(送信はしません)。初期値は \(initialKeyText) です。")
        case .commitAndSend:
            return String(localized: "挿入したあと Enter を送って送信します。送信は取り消せません。初期値は \(initialKeyText) です。")
        }
    }
}

/// 記録ボックスで押されたキー。
struct PanelShortcutCandidate: Equatable {
    let shortcut: PanelShortcut
    let characters: String
}

enum PanelShortcutRejection: Equatable {
    case missingModifier
    case reservedForClosing
    case reservedForHiding
    case reservedForEditing
    case reservedForPanelCommands
    case usedByHotkey
    case usedByOtherRole(PanelShortcutRole)

    func message(for shortcut: PanelShortcut) -> String {
        let key = shortcut.displayText
        switch self {
        case .missingModifier:
            return String(localized: "⌘・⌥・⌃・⇧ のどれかと組み合わせたキーを押してください。")
        case .reservedForClosing:
            return String(localized: "esc はパネルを閉じるキーのため、修飾キーと組み合わせても登録できません。")
        case .reservedForHiding:
            return String(localized: "\(key) はパネルを閉じるキーのため、登録できません。")
        case .reservedForEditing:
            return String(localized: "\(key) は入力欄の編集ショートカットで使っているため、登録できません。")
        case .reservedForPanelCommands:
            return String(localized: "\(key) はパネルの\(PanelCommandKeys.operationNamesText)の操作(\(PanelCommandKeys.keysText))で使っているため、登録できません。")
        case .usedByHotkey:
            return String(localized: "\(key) は「パネルを開く・閉じる」で使っているため、登録できません。")
        case .usedByOtherRole(.commitAndSend):
            return String(localized: "\(key) は「確定+送信キー」で使っているため、登録できません。")
        case .usedByOtherRole(.commit):
            return String(localized: "\(key) は「確定+挿入キー」で使っているため、登録できません。")
        }
    }
}

enum PanelShortcutRules {
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
        if isReservedForHiding(candidate) {
            return .reservedForHiding
        }
        if isReservedForEditing(candidate) {
            return .reservedForEditing
        }
        if ReservedPanelKeys.isReserved(candidate) {
            return .reservedForPanelCommands
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

    private static func isReservedForHiding(_ candidate: PanelShortcutCandidate) -> Bool {
        candidate.shortcut.modifiers == [.command] && candidate.characters == "h"
    }

    private static func isReservedForEditing(_ candidate: PanelShortcutCandidate) -> Bool {
        let shortcut = candidate.shortcut
        if EditorKeyCommand.isReservedKeyEquivalent(modifiers: shortcut.modifiers, character: candidate.characters) {
            return true
        }
        let input = PanelKeyInput(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, hasMarkedText: false)
        return LineEditing.arrowCommand(for: input) != nil
    }
}
