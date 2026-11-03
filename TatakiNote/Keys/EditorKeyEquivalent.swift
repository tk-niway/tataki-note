import AppKit

/// ⌘ と文字の組み合わせ。
struct EditorKeyEquivalent: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let character: String
}
