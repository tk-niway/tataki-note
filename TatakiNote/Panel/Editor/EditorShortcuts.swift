import Foundation

/// パネルの入力欄で使えるショートカットキーの1行(「ホットキーとキー操作」の一覧に出す)。
struct EditorShortcut: Identifiable, Equatable {
    let id: String
    let keys: String
    let action: String
}

/// 分類ごとにまとめたショートカットキー。
struct EditorShortcutGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let shortcuts: [EditorShortcut]
}

/// ショートカットキーの一覧。
enum EditorShortcuts {
    /// 「ショートカットキー」の一覧の下に出す説明文。
    static let settingDescription = String(localized: "割り当ては変えられません。確定のキーは上の「確定+挿入キー」「確定+送信キー」で確かめられます。")

    static let all: [EditorShortcut] = EditorKeyCommand.allCases.compactMap(\.listing)

    /// パネルの操作のキーの表(`PanelCommandKeys`)から作る、一覧の行。
    static let panelCommands: [EditorShortcut] = PanelCommandKeys.all.map(\.listing)

    /// 検索・置換のキーの一覧の行。
    static let find: [EditorShortcut] = [
        EditorShortcut(id: "findOpen", keys: "⌘F", action: String(localized: "検索バーを出す(選択中の文字を検索語にする)")),
        EditorShortcut(id: "findReplaceOpen", keys: "⌥⌘F", action: String(localized: "置換の欄まで出す")),
        EditorShortcut(id: "findNext", keys: "↩ / ⌘G", action: String(localized: "次の一致へ")),
        EditorShortcut(id: "findPrevious", keys: "⇧↩ / ⇧⌘G", action: String(localized: "前の一致へ")),
        EditorShortcut(id: "findToggleOptions", keys: "⌥⌘C / ⌥⌘W / ⌥⌘R", action: String(localized: "大文字と小文字の区別・単語単位・正規表現を切り替える")),
        EditorShortcut(id: "findPreserveCase", keys: "⌥⌘P", action: String(localized: "置換で大文字と小文字を保持する")),
        EditorShortcut(id: "findReplaceOne", keys: "⇧⌘1", action: String(localized: "次を置換する(置換欄では ↩)")),
        EditorShortcut(id: "findReplaceAll", keys: "⌥⌘↩", action: String(localized: "すべて置換する(置換欄では ⌘↩)")),
        EditorShortcut(id: "findClose", keys: "esc", action: String(localized: "検索バーを閉じる")),
    ]

    /// 「行の操作」「コピーと貼り付け」「下書き」「検索と置換」「表示」の5つの分類。
    static let groups: [EditorShortcutGroup] = [
        EditorShortcutGroup(
            id: "line",
            title: String(localized: "行の操作"),
            shortcuts: shortcuts(withIDs: ["moveLine", "duplicateLine", "selectLine", "selectWord"])
        ),
        EditorShortcutGroup(
            id: "clipboard",
            title: String(localized: "コピーと貼り付け"),
            shortcuts: shortcuts(withIDs: ["copyLine", "cutLine", "pasteLine"])
        ),
        EditorShortcutGroup(
            id: "drafts",
            title: String(localized: "下書き"),
            shortcuts: shortcuts(withIDs: ["saveDraft", "exportToFile", "newDraft", "toggleMode", "searchDrafts"])
        ),
        EditorShortcutGroup(
            id: "find",
            title: String(localized: "検索と置換"),
            shortcuts: find
        ),
        EditorShortcutGroup(
            id: "view",
            title: String(localized: "表示"),
            shortcuts: shortcuts(withIDs: ["toggleSidebar", "openSettings"])
        ),
    ]

    private static func shortcuts(withIDs ids: [String]) -> [EditorShortcut] {
        let candidates = all + panelCommands + find
        return ids.compactMap { id in candidates.first { $0.id == id } }
    }
}
