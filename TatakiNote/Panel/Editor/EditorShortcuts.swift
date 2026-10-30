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

    /// 「行の操作」「コピーと貼り付け」「下書き」「表示」の4つの分類。
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
            id: "view",
            title: String(localized: "表示"),
            shortcuts: shortcuts(withIDs: ["toggleSidebar", "openSettings"])
        ),
    ]

    private static func shortcuts(withIDs ids: [String]) -> [EditorShortcut] {
        let candidates = all + panelCommands
        return ids.compactMap { id in candidates.first { $0.id == id } }
    }
}
