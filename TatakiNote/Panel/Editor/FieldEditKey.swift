import AppKit

/// 1行の欄(検索欄・置換欄・保存ダイアログの名前の欄)で、⌘ のキーに当てる編集の操作。
enum FieldEditAction: Equatable {
    case cut
    case copy
    case paste
    case selectAll
    case undo
    case redo
}

/// 1行の欄の ⌘ のキーを、編集の操作に対応づける。
enum FieldEditKey {
    /// 押されたキーに当たる編集の操作。当たらなければ nil。
    static func action(modifiers: NSEvent.ModifierFlags, character: String) -> FieldEditAction? {
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        switch EditorKeyCommand.command(modifiers: relevant, character: character) {
        case .cut: return .cut
        case .copy: return .copy
        case .paste: return .paste
        case .selectAll: return .selectAll
        case .undo: return .undo
        case .redo: return .redo
        case .moveLines, .duplicateLines, .selectLine, .selectWord, nil: return nil
        }
    }
}
