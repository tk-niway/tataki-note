import AppKit

/// ⌘ と文字の組み合わせ。
struct EditorKeyEquivalent: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let character: String
}

/// 入力欄の編集キーの操作。並びは「ショートカットキー」の一覧の並び。
enum EditorKeyCommand: CaseIterable {
    case moveLines
    case duplicateLines
    case copy
    case cut
    case paste
    case selectLine
    case selectWord
    case selectAll
    case undo
    case redo

    private static let otherReserved: [EditorKeyEquivalent] = [
        EditorKeyEquivalent(modifiers: [.command], character: "h"),
    ]

    /// ⌘ と文字で押すキー(矢印で押す操作は nil)。
    var keyEquivalent: EditorKeyEquivalent? {
        switch self {
        case .moveLines, .duplicateLines: return nil
        case .copy: return EditorKeyEquivalent(modifiers: [.command], character: "c")
        case .cut: return EditorKeyEquivalent(modifiers: [.command], character: "x")
        case .paste: return EditorKeyEquivalent(modifiers: [.command], character: "v")
        case .selectLine: return EditorKeyEquivalent(modifiers: [.command], character: "l")
        case .selectWord: return EditorKeyEquivalent(modifiers: [.command], character: "d")
        case .selectAll: return EditorKeyEquivalent(modifiers: [.command], character: "a")
        case .undo: return EditorKeyEquivalent(modifiers: [.command], character: "z")
        case .redo: return EditorKeyEquivalent(modifiers: [.command, .shift], character: "z")
        }
    }

    /// パネルの入力欄だけで効くか(練習用の入力欄では効かない)。
    var isPanelOnly: Bool {
        switch self {
        case .moveLines, .duplicateLines, .selectLine, .selectWord: return true
        case .copy, .cut, .paste, .selectAll, .undo, .redo: return false
        }
    }

    /// 「ショートカットキー」の一覧に出す行(出さないものは nil)。
    var listing: EditorShortcut? {
        switch self {
        case .moveLines:
            return EditorShortcut(
                id: "moveLine",
                keys: String(localized: "⌥↑ / ⌥↓"),
                action: String(localized: "行を上 / 下の行と入れ替える")
            )
        case .duplicateLines:
            return EditorShortcut(
                id: "duplicateLine",
                keys: String(localized: "⇧⌥↑ / ⇧⌥↓"),
                action: String(localized: "行を下に複製する")
            )
        case .copy:
            return EditorShortcut(
                id: "copyLine",
                keys: String(localized: "⌘C"),
                action: String(localized: "選択なしで行ごとコピー")
            )
        case .cut:
            return EditorShortcut(
                id: "cutLine",
                keys: String(localized: "⌘X"),
                action: String(localized: "選択なしで行ごと切り取り")
            )
        case .paste:
            return EditorShortcut(
                id: "pasteLine",
                keys: String(localized: "⌘V"),
                action: String(localized: "行ごとコピー・切り取りした行を上に貼り付け")
            )
        case .selectLine:
            return EditorShortcut(
                id: "selectLine",
                keys: String(localized: "⌘L"),
                action: String(localized: "行を選択(続けて押すと下へ広げる)")
            )
        case .selectWord:
            return EditorShortcut(
                id: "selectWord",
                keys: String(localized: "⌘D"),
                action: String(localized: "カーソルのある単語を選択")
            )
        case .selectAll, .undo, .redo:
            return nil
        }
    }

    /// 押された ⌘ のキー(修飾キーは `PanelShortcut.relevantModifiers` に絞ったもの、文字は小文字)に当たる操作。
    static func command(modifiers: NSEvent.ModifierFlags, character: String) -> EditorKeyCommand? {
        let pressed = EditorKeyEquivalent(modifiers: modifiers, character: character)
        return allCases.first { $0.keyEquivalent == pressed }
    }

    /// 記録ボックスで登録できない ⌘ のキーか(編集キーと、⌘H)。
    static func isReservedKeyEquivalent(modifiers: NSEvent.ModifierFlags, character: String) -> Bool {
        let pressed = EditorKeyEquivalent(modifiers: modifiers, character: character)
        return command(modifiers: modifiers, character: character) != nil || otherReserved.contains(pressed)
    }
}
