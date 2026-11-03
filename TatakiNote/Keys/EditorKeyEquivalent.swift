import AppKit

/// ⌘ と文字の組み合わせ。
struct EditorKeyEquivalent: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let character: String
}

extension EditorKeyEquivalent {
    /// 押されたキーがこのキーかを返す。修飾キーは `PanelShortcut.relevantModifiers` に絞って比べ、文字は小文字で渡す。
    func matches(modifiers: NSEvent.ModifierFlags, character: String) -> Bool {
        self.modifiers == modifiers.intersection(PanelShortcut.relevantModifiers) && self.character == character
    }
}
