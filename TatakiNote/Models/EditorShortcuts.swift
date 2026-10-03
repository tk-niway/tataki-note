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
    static let settingDescription = String(localized: "パネルの入力欄で使えるキーです(割り当ては変えられません)。改行・閉じる・確定のキーは、パネルの下の帯と、上の「確定キー」「確定+送信キー」で確かめられます。")

    static let all: [EditorShortcut] = [
        EditorShortcut(
            id: "moveLine",
            keys: String(localized: "⌥↑ / ⌥↓"),
            action: String(localized: "行を上 / 下の行と入れ替える")
        ),
        EditorShortcut(
            id: "duplicateLine",
            keys: String(localized: "⇧⌥↑ / ⇧⌥↓"),
            action: String(localized: "行を下に複製する")
        ),
        EditorShortcut(
            id: "copyLine",
            keys: String(localized: "⌘C"),
            action: String(localized: "選択なしで行ごとコピー")
        ),
        EditorShortcut(
            id: "cutLine",
            keys: String(localized: "⌘X"),
            action: String(localized: "選択なしで行ごと切り取り")
        ),
        EditorShortcut(
            id: "pasteLine",
            keys: String(localized: "⌘V"),
            action: String(localized: "行ごとコピー・切り取りした行を上に貼り付け")
        ),
        EditorShortcut(
            id: "selectLine",
            keys: String(localized: "⌘L"),
            action: String(localized: "行を選択(続けて押すと下へ広げる)")
        ),
        EditorShortcut(
            id: "selectWord",
            keys: String(localized: "⌘D"),
            action: String(localized: "カーソルのある単語を選択")
        ),
    ]
}
