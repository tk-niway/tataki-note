import AppKit

/// 検索バーの操作。
enum FindKeyAction: Equatable {
    case open(revealsReplace: Bool)
    case next
    case previous
    case toggle(FindOption)
    case replaceOne
    case replaceAll
    case close
    case focusFindField
    case focusReplaceField
    case focusEditor
    case insertNewlineInField
    case swallow
}

/// キーを押したときのフォーカスの場所。
enum FindFocus: Equatable {
    case editor
    case findField
    case replaceField
    case other
}

/// 押すキー(文字か、キーコード)。
enum FindKeyStroke: Equatable {
    case character(String)
    case keyCode(UInt16)
}

/// どこにフォーカスがあっても効く検索のキーの1行。
struct FindKey: Equatable {
    let action: FindKeyAction
    let modifiers: NSEvent.ModifierFlags
    let stroke: FindKeyStroke
    let keyText: String
}

/// 「パネルの中で使えるキー」の一覧の、検索と置換の1行。
struct FindKeyListing: Equatable {
    /// 一覧の行の id。
    let id: String
    /// 表に無いキーの表記。表のキーより前に並べる。
    let otherKeys: [String]
    /// 表の行の操作。この順に表の表記を並べる。
    let actions: [FindKeyAction]
    /// 一覧に出す操作の説明。
    let listingAction: String

    /// 一覧の1行。
    var listing: EditorShortcut {
        let tableKeys = actions.compactMap { action in FindKeys.global.first { $0.action == action }?.keyText }
        return EditorShortcut(id: id, keys: (otherKeys + tableKeys).joined(separator: " / "), action: listingAction)
    }
}

/// 検索のキーの表。
enum FindKeys {
    private static let digitOneKeyCode: UInt16 = 18

    static let global: [FindKey] = [
        FindKey(action: .open(revealsReplace: false), modifiers: [.command], stroke: .character("f"), keyText: "⌘F"),
        FindKey(action: .open(revealsReplace: true), modifiers: [.command, .option], stroke: .character("f"), keyText: "⌥⌘F"),
        FindKey(action: .next, modifiers: [.command], stroke: .character("g"), keyText: "⌘G"),
        FindKey(action: .previous, modifiers: [.command, .shift], stroke: .character("g"), keyText: "⇧⌘G"),
        FindKey(action: .toggle(.caseSensitive), modifiers: [.command, .option], stroke: .character("c"), keyText: "⌥⌘C"),
        FindKey(action: .toggle(.wholeWord), modifiers: [.command, .option], stroke: .character("w"), keyText: "⌥⌘W"),
        FindKey(action: .toggle(.regex), modifiers: [.command, .option], stroke: .character("r"), keyText: "⌥⌘R"),
        FindKey(action: .toggle(.preserveCase), modifiers: [.command, .option], stroke: .character("p"), keyText: "⌥⌘P"),
        FindKey(action: .replaceOne, modifiers: [.command, .shift], stroke: .keyCode(digitOneKeyCode), keyText: "⇧⌘1"),
        FindKey(action: .replaceAll, modifiers: [.command, .option], stroke: .keyCode(KeyCode.returnKey), keyText: "⌥⌘↩"),
    ]

    /// 「検索と置換」の一覧の行の定義。並びは一覧の並び。
    static let listings: [FindKeyListing] = [
        FindKeyListing(
            id: "findOpen",
            otherKeys: [],
            actions: [.open(revealsReplace: false)],
            listingAction: String(localized: "検索バーを出す(選択中の文字を検索語にする)")
        ),
        FindKeyListing(
            id: "findReplaceOpen",
            otherKeys: [],
            actions: [.open(revealsReplace: true)],
            listingAction: String(localized: "置換の欄まで出す")
        ),
        FindKeyListing(
            id: "findNext",
            otherKeys: ["↩"],
            actions: [.next],
            listingAction: String(localized: "次の一致へ")
        ),
        FindKeyListing(
            id: "findPrevious",
            otherKeys: ["⇧↩"],
            actions: [.previous],
            listingAction: String(localized: "前の一致へ")
        ),
        FindKeyListing(
            id: "findToggleOptions",
            otherKeys: [],
            actions: [.toggle(.caseSensitive), .toggle(.wholeWord), .toggle(.regex)],
            listingAction: String(localized: "大文字と小文字の区別・単語単位・正規表現を切り替える")
        ),
        FindKeyListing(
            id: "findPreserveCase",
            otherKeys: [],
            actions: [.toggle(.preserveCase)],
            listingAction: String(localized: "置換で大文字と小文字を保持する")
        ),
        FindKeyListing(
            id: "findReplaceOne",
            otherKeys: [],
            actions: [.replaceOne],
            listingAction: String(localized: "次を置換する(置換欄では ↩)")
        ),
        FindKeyListing(
            id: "findReplaceAll",
            otherKeys: [],
            actions: [.replaceAll],
            listingAction: String(localized: "すべて置換する(置換欄では ⌘↩)")
        ),
        FindKeyListing(
            id: "findClose",
            otherKeys: ["esc"],
            actions: [],
            listingAction: String(localized: "検索バーを閉じる")
        ),
    ]

    /// 押されたキーに当たる検索のキーの行。
    static func globalKey(for input: PanelKeyInput) -> FindKey? {
        let modifiers = input.modifiers.intersection(PanelShortcut.relevantModifiers)
        let keyCode = input.keyCode == KeyCode.keypadEnter ? KeyCode.returnKey : input.keyCode
        let character = input.characters.lowercased()
        return global.first { key in
            guard key.modifiers == modifiers else { return false }
            switch key.stroke {
            case .character(let expected): return character == expected
            case .keyCode(let expected): return keyCode == expected
            }
        }
    }

    /// 保存値のキーが検索のキーかを返す。
    static func isReserved(_ shortcut: PanelShortcut) -> Bool {
        global.contains { key in
            guard key.modifiers == shortcut.modifiers else { return false }
            switch key.stroke {
            case .character: return key.keyText == shortcut.displayText
            case .keyCode(let expected): return shortcut.keyCode == expected
            }
        }
    }

    /// 記録で押されたキーが検索のキーかを返す。
    static func isReserved(_ candidate: PanelShortcutCandidate) -> Bool {
        let shortcut = candidate.shortcut
        return global.contains { key in
            guard key.modifiers == shortcut.modifiers else { return false }
            switch key.stroke {
            case .character(let expected): return candidate.characters.lowercased() == expected
            case .keyCode(let expected): return shortcut.keyCode == expected
            }
        }
    }

    /// 登録できないときの説明に並べるキー。
    static var keysText: String {
        global.map(\.keyText).joined(separator: "・")
    }

    /// 検索欄・置換欄で押した ⌘ のキーに当たる欄の編集の操作。欄を編集中でない・変換中なら `nil`。
    static func fieldEditAction(
        modifiers: NSEvent.ModifierFlags,
        character: String,
        isEditing: Bool,
        hasMarkedText: Bool
    ) -> FieldEditAction? {
        guard isEditing, !hasMarkedText else { return nil }
        return FieldEditKey.action(modifiers: modifiers, character: character)
    }
}

/// 押されたキーを、フォーカスの場所と検索バーの状態に応じた検索バーの操作にする。
enum FindKeyResolver {
    /// 検索バーの操作にならないキーは `nil`(今までの処理へ渡す)。
    static func action(
        for input: PanelKeyInput,
        focus: FindFocus,
        isBarVisible: Bool,
        isReplaceShown: Bool
    ) -> FindKeyAction? {
        if input.hasMarkedText {
            return nil
        }
        if let key = FindKeys.globalKey(for: input) {
            switch key.action {
            case .replaceOne, .replaceAll: return isBarVisible ? key.action : .swallow
            default: return key.action
            }
        }
        switch focus {
        case .findField, .replaceField:
            guard isBarVisible else { return nil }
            return fieldAction(for: input, focus: focus, isReplaceShown: isReplaceShown)
        case .editor:
            return input.keyCode == KeyCode.escape && isBarVisible ? .close : nil
        case .other:
            return nil
        }
    }

    private static func fieldAction(for input: PanelKeyInput, focus: FindFocus, isReplaceShown: Bool) -> FindKeyAction? {
        let modifiers = input.modifiers.intersection(PanelShortcut.relevantModifiers)
        switch input.keyCode {
        case KeyCode.escape:
            return modifiers.isEmpty ? .close : nil
        case KeyCode.returnKey, KeyCode.keypadEnter:
            return returnAction(modifiers: modifiers, focus: focus)
        case KeyCode.tab:
            if modifiers.isEmpty {
                if focus == .replaceField { return .focusEditor }
                return isReplaceShown ? .focusReplaceField : .focusEditor
            }
            if modifiers == [.shift], focus == .replaceField {
                return .focusFindField
            }
            return nil
        case KeyCode.downArrow:
            return modifiers == [.command] ? .focusEditor : nil
        default:
            return nil
        }
    }

    private static func returnAction(modifiers: NSEvent.ModifierFlags, focus: FindFocus) -> FindKeyAction {
        if modifiers == [.control] {
            return .insertNewlineInField
        }
        if focus == .findField {
            if modifiers.isEmpty { return .next }
            if modifiers == [.shift] { return .previous }
            return .swallow
        }
        if modifiers.isEmpty { return .replaceOne }
        if modifiers == [.command] { return .replaceAll }
        return .swallow
    }
}
