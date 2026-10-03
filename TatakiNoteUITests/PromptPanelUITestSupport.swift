import XCTest

extension XCUIElement {
    static let promptPanelPlaceholder = "ここにプロンプトを書く…"

    /// 入力欄の文章。空の入力欄の値がプレースホルダーの文になる場合は空文字を返す。
    var promptPanelText: String {
        let text = value as? String ?? ""
        return text == Self.promptPanelPlaceholder ? "" : text
    }
}
