import Foundation

/// パネルの入力欄で使えるショートカットキーの1行(「キー」の一覧に出す)。
struct EditorShortcut: Identifiable, Equatable {
    let id: String
    let keys: String
    let action: String
}

/// ショートカットキーの一覧。
enum EditorShortcuts {
    /// 「ショートカットキー」の一覧の下に出す説明文。
    static let settingDescription = String(localized: "パネルの入力欄で使えるキーです(割り当ては変えられません)。改行・閉じる・確定のキーは、パネルの下の帯と、上の「確定+挿入キー」「確定+送信キー」で確かめられます。")

    static let all: [EditorShortcut] = EditorKeyCommand.allCases.compactMap(\.listing)

    /// 「ショートカットキー」の一覧で編集キーの後に出す、検索・保存・新規の行。
    static let panelCommands: [EditorShortcut] = [
        EditorShortcut(id: "searchDrafts", keys: "⌘K", action: String(localized: "下書きと履歴を検索する(サイドバーを開く)")),
        EditorShortcut(id: "saveDraft", keys: "⌘S", action: String(localized: "下書きに保存する")),
        EditorShortcut(id: "newDraft", keys: "⌘N", action: String(localized: "新しい書きかけにする")),
    ]
}
