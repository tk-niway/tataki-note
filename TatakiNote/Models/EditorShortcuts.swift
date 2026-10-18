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

    /// 「ショートカットキー」の一覧で編集キーの後に出す、検索・保存・新規・サイドバーの開閉・設定の行。
    static let panelCommands: [EditorShortcut] = [
        EditorShortcut(id: "searchDrafts", keys: "⌘K", action: String(localized: "下書きと履歴を検索する(サイドバーを開く)")),
        EditorShortcut(id: "saveDraft", keys: "⌘S", action: String(localized: "下書きに保存する")),
        EditorShortcut(id: "newDraft", keys: "⌘N", action: String(localized: "新しい書きかけにする")),
        EditorShortcut(id: "toggleMode", keys: "⌘E", action: String(localized: "インサートとノートを切り替える")),
        EditorShortcut(id: "toggleSidebar", keys: "⌘B", action: String(localized: "サイドバーを開く・閉じる")),
        EditorShortcut(id: "openSettings", keys: "⌘,", action: String(localized: "設定を開く")),
        EditorShortcut(id: "exportToFile", keys: "⇧⌘S", action: String(localized: "ファイルに書き出す")),
    ]

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
