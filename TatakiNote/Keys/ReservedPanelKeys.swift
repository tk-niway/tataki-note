import AppKit

/// パネルの検索・保存・新規・モードの切り替え・サイドバーの開閉・設定・ファイルへの書き出しに使う ⌘K・⌘S・⌘N・⌘E・⌘B・⌘,・⇧⌘S。
enum ReservedPanelKeys {
    /// 予約のキーの修飾キーと文字の組。
    static let keys: [EditorKeyEquivalent] = [
        EditorKeyEquivalent(modifiers: [.command], character: "k"),
        EditorKeyEquivalent(modifiers: [.command], character: "s"),
        EditorKeyEquivalent(modifiers: [.command], character: "n"),
        EditorKeyEquivalent(modifiers: [.command], character: "e"),
        EditorKeyEquivalent(modifiers: [.command], character: "b"),
        EditorKeyEquivalent(modifiers: [.command], character: ","),
        EditorKeyEquivalent(modifiers: [.command, .shift], character: "s"),
    ]

    /// 押されたキー(修飾キーは `PanelShortcut.relevantModifiers` に絞ったもの、文字は小文字)が予約のキーかを返す。
    static func contains(modifiers: NSEvent.ModifierFlags, character: String) -> Bool {
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        return keys.contains { $0.modifiers == relevant && $0.character == character }
    }

    /// 記録で押されたキーが予約のキーかを返す。
    static func isReserved(_ candidate: PanelShortcutCandidate) -> Bool {
        contains(modifiers: candidate.shortcut.modifiers, character: candidate.characters.lowercased())
    }

    /// 保存値のキーが、今のキー配列で予約のキーに当たるかを返す。
    static func isReserved(_ shortcut: PanelShortcut) -> Bool {
        keys.contains { key in
            key.modifiers == shortcut.modifiers && displayText(of: key) == shortcut.displayText
        }
    }

    private static func displayText(of key: EditorKeyEquivalent) -> String {
        (key.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + key.character.uppercased()
    }

    struct Migration: Equatable {
        var commitKey: PanelShortcut?
        var commitAndSendKey: PanelShortcut?
        var shouldResetHotkey: Bool
    }

    /// 確定キーとホットキーを、予約のキーを避けた値に直した結果を返す。
    static func migrate(
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?,
        hotkey: PanelShortcut?,
        defaultHotkey: PanelShortcut?,
        isReserved: (PanelShortcut) -> Bool = ReservedPanelKeys.isReserved
    ) -> Migration {
        let shouldResetHotkey = hotkey.map(isReserved) ?? false
        let hotkeyAfter = shouldResetHotkey ? defaultHotkey : hotkey

        func needsReset(_ key: PanelShortcut?) -> Bool {
            guard let key else { return false }
            return isReserved(key) || (shouldResetHotkey && key == hotkeyAfter)
        }

        var commit = needsReset(commitKey) ? PanelShortcut.defaultCommitKey : commitKey
        var commitAndSend = needsReset(commitAndSendKey) ? PanelShortcut.defaultCommitAndSendKey : commitAndSendKey

        let wasReset = commit != commitKey || commitAndSend != commitAndSendKey
        if wasReset, let key = commit, key == commitAndSend {
            commit = PanelShortcut.defaultCommitKey
            commitAndSend = PanelShortcut.defaultCommitAndSendKey
        }

        if commit != commitKey, let key = commit, key == hotkeyAfter {
            commit = nil
        }
        if commitAndSend != commitAndSendKey, let key = commitAndSend, key == hotkeyAfter {
            commitAndSend = nil
        }
        return Migration(commitKey: commit, commitAndSendKey: commitAndSend, shouldResetHotkey: shouldResetHotkey)
    }

    /// 起動時に設定とホットキーへ当てはめる。
    static func apply(
        to settings: AppSettings,
        hotkey: PanelShortcut?,
        defaultHotkey: PanelShortcut?,
        resetHotkey: () -> Void
    ) {
        let migration = migrate(
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey,
            hotkey: hotkey,
            defaultHotkey: defaultHotkey
        )
        if migration.commitKey != settings.commitKey {
            settings.commitKey = migration.commitKey
        }
        if migration.commitAndSendKey != settings.commitAndSendKey {
            settings.commitAndSendKey = migration.commitAndSendKey
        }
        if migration.shouldResetHotkey {
            resetHotkey()
        }
    }
}
