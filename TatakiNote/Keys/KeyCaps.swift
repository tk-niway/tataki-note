import Foundation

/// キーの表記を、1つずつのキーに分ける。
enum KeyCaps {
    private static let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
    private static let alternativeSeparator = " / "

    /// 先頭から続く修飾キーを1つずつ、残りを1つにまとめて返す。空なら空の配列。
    static func caps(in text: String) -> [String] {
        var caps: [String] = []
        var rest = Substring(text)
        while let first = rest.first, modifierSymbols.contains(first) {
            caps.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty {
            caps.append(String(rest))
        }
        return caps
    }

    /// 「 / 」で区切られた表記を、組ごとに分けて返す。
    static func alternatives(in keys: String) -> [[String]] {
        keys.components(separatedBy: alternativeSeparator)
            .map { caps(in: $0) }
            .filter { !$0.isEmpty }
    }
}
