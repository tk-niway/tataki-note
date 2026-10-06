import AppKit

/// パネルの検索・保存・新規に使う ⌘K・⌘S・⌘N。
enum ReservedPanelKeys {
    static let characters: [String] = ["k", "s", "n"]

    /// 記録で押されたキーが ⌘K・⌘S・⌘N のどれかを返す。
    static func isReserved(_ candidate: PanelShortcutCandidate) -> Bool {
        candidate.shortcut.modifiers == [.command] && characters.contains(candidate.characters.lowercased())
    }

    /// 保存値のキーが、今のキー配列で ⌘K・⌘S・⌘N に当たるかを返す。
    static func isReserved(_ shortcut: PanelShortcut) -> Bool {
        shortcut.modifiers == [.command] && characters.map { "⌘" + $0.uppercased() }.contains(shortcut.displayText)
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
