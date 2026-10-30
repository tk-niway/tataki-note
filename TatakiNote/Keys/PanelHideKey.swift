import AppKit

/// アプリを隠すキー(⌘H)の判定。
enum PanelHideKey {
    /// 修飾キーが ⌘ だけで、文字が H のとき true。
    static func matches(modifiers: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        modifiers.intersection(PanelShortcut.relevantModifiers) == [.command]
            && charactersIgnoringModifiers?.lowercased() == "h"
    }
}
