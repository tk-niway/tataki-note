import AppKit

/// パネルの操作のキーの1行。
struct PanelCommandKey: Equatable {
    /// キーで選ばれる操作。
    let action: PanelKeyAction
    /// 押すキー(修飾キーは `PanelShortcut.relevantModifiers` の中、文字は小文字)。
    let key: EditorKeyEquivalent
    /// 「パネルの中で使えるキー」の一覧の行の id。
    let listingID: String
    /// 一覧に出す操作の説明。
    let listingAction: String
    /// 登録できないときの説明に並べる操作の名前。
    let operationName: String

    /// キーの表示("⌘K"・"⇧⌘S")。
    var keyText: String {
        (key.modifiers.contains(.shift) ? "⇧" : "") + "⌘" + key.character.uppercased()
    }

    /// 一覧の1行。
    var listing: EditorShortcut {
        EditorShortcut(id: listingID, keys: keyText, action: listingAction)
    }
}

/// パネルの操作のキーの表。並びは設定の一覧と、登録できないときの説明の並び。
enum PanelCommandKeys {
    static let all: [PanelCommandKey] = [
        PanelCommandKey(
            action: .openSearch,
            key: EditorKeyEquivalent(modifiers: [.command], character: "k"),
            listingID: "searchDrafts",
            listingAction: String(localized: "下書きと履歴を検索する(サイドバーを開く)"),
            operationName: String(localized: "検索")
        ),
        PanelCommandKey(
            action: .saveDraft,
            key: EditorKeyEquivalent(modifiers: [.command], character: "s"),
            listingID: "saveDraft",
            listingAction: String(localized: "下書きに保存する"),
            operationName: String(localized: "下書きの保存")
        ),
        PanelCommandKey(
            action: .newDraft,
            key: EditorKeyEquivalent(modifiers: [.command], character: "n"),
            listingID: "newDraft",
            listingAction: String(localized: "新しい書きかけにする"),
            operationName: String(localized: "新しい書きかけ")
        ),
        PanelCommandKey(
            action: .toggleMode,
            key: EditorKeyEquivalent(modifiers: [.command], character: "e"),
            listingID: "toggleMode",
            listingAction: String(localized: "インサートとノートを切り替える"),
            operationName: String(localized: "モードの切り替え")
        ),
        PanelCommandKey(
            action: .toggleSidebar,
            key: EditorKeyEquivalent(modifiers: [.command], character: "b"),
            listingID: "toggleSidebar",
            listingAction: String(localized: "サイドバーを開く・閉じる"),
            operationName: String(localized: "サイドバーの開閉")
        ),
        PanelCommandKey(
            action: .openSettings,
            key: EditorKeyEquivalent(modifiers: [.command], character: ","),
            listingID: "openSettings",
            listingAction: String(localized: "設定を開く"),
            operationName: String(localized: "設定を開く")
        ),
        PanelCommandKey(
            action: .exportToFile,
            key: EditorKeyEquivalent(modifiers: [.command, .shift], character: "s"),
            listingID: "exportToFile",
            listingAction: String(localized: "ファイルに書き出す"),
            operationName: String(localized: "ファイルへの書き出し")
        ),
    ]

    /// 押されたキーに当たる行。修飾キーは `PanelShortcut.relevantModifiers` に絞って比べ、文字は小文字で渡す。
    static func row(modifiers: NSEvent.ModifierFlags, character: String) -> PanelCommandKey? {
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        return all.first { $0.key.modifiers == relevant && $0.key.character == character }
    }

    /// 登録できないときの説明に並べる操作の名前。
    static var operationNamesText: String {
        all.map(\.operationName).joined(separator: "・")
    }

    /// 登録できないときの説明に並べるキー。
    static var keysText: String {
        all.map(\.keyText).joined(separator: "・")
    }
}
