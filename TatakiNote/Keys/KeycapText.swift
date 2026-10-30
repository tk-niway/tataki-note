/// キーの表示文字をキーキャップ 1 つずつに分ける。
enum KeycapText {
    private static let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    /// 先頭に続く修飾キーの記号(⌃⌥⇧⌘)を 1 つずつ、残りをまとめて 1 つにして返す。
    static func keys(of displayText: String) -> [String] {
        var keys: [String] = []
        var rest = Substring(displayText)
        while let first = rest.first, modifierSymbols.contains(first) {
            keys.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty {
            keys.append(String(rest))
        }
        return keys
    }
}
