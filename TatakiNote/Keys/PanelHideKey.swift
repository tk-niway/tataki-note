import AppKit

/// アプリを隠すキー(⌘H)の判定。
enum PanelHideKey {
    /// アプリを隠すキー(⌘H)。
    static let key = EditorKeyEquivalent(modifiers: [.command], character: "h")

    /// 修飾キーが ⌘ だけで、文字が H のとき true。
    static func matches(modifiers: NSEvent.ModifierFlags, charactersIgnoringModifiers: String?) -> Bool {
        key.matches(modifiers: modifiers, character: charactersIgnoringModifiers?.lowercased() ?? "")
    }
}
