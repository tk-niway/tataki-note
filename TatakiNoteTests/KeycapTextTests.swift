import Testing
@testable import TatakiNote

struct KeycapTextTests {
    @Test("AC-7: キーの表示文字は、先頭の修飾キーを 1 つずつ、残りを 1 つにまとめてキーキャップに分ける", arguments: [
        ("⇧⌘↩", ["⇧", "⌘", "↩"]),
        ("⌘↩", ["⌘", "↩"]),
        ("⇧↩", ["⇧", "↩"]),
        ("⌃⌥Space", ["⌃", "⌥", "Space"]),
        ("⌘F1", ["⌘", "F1"]),
        ("↩", ["↩"]),
        ("esc", ["esc"]),
        ("", []),
        ("⌘", ["⌘"]),
        ("⌘⇧", ["⌘", "⇧"]),
    ] as [(String, [String])])
    func splitsIntoKeycaps(displayText: String, expected: [String]) {
        #expect(KeycapText.keys(of: displayText) == expected)
    }
}
