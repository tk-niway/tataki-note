import Testing
@testable import TatakiNote

struct KeyCapsTests {
    @Test("AC-21: キーの表記は先頭の修飾キーを1つずつ、残りを1つにまとめて分かれる")
    func splitsModifiersAndKey() {
        #expect(KeyCaps.caps(in: "⇧⌘↩") == ["⇧", "⌘", "↩"])
        #expect(KeyCaps.caps(in: "⌥⇧Space") == ["⌥", "⇧", "Space"])
        #expect(KeyCaps.caps(in: "⌘,") == ["⌘", ","])
        #expect(KeyCaps.caps(in: "⌃⌥⇧⌘K") == ["⌃", "⌥", "⇧", "⌘", "K"])
        #expect(KeyCaps.caps(in: "F5") == ["F5"])
        #expect(KeyCaps.caps(in: "esc") == ["esc"])
        #expect(KeyCaps.caps(in: "⌘") == ["⌘"])
        #expect(KeyCaps.caps(in: "") == [])
    }

    @Test("AC-21: 「 / 」で区切られた表記は組ごとに分かれる")
    func splitsAlternatives() {
        #expect(KeyCaps.alternatives(in: "⌥↑ / ⌥↓") == [["⌥", "↑"], ["⌥", "↓"]])
        #expect(KeyCaps.alternatives(in: "⇧⌥↑ / ⇧⌥↓") == [["⇧", "⌥", "↑"], ["⇧", "⌥", "↓"]])
        #expect(KeyCaps.alternatives(in: "⌘L") == [["⌘", "L"]])
        #expect(KeyCaps.alternatives(in: "") == [])
    }

    @Test("AC-21: 一覧のどの表記も、キーキャップに分けて元の表記に戻せる")
    func capsOfEveryListedShortcutRoundTrip() {
        let shortcuts = EditorShortcuts.all + EditorShortcuts.panelCommands
        for shortcut in shortcuts {
            let alternatives = KeyCaps.alternatives(in: shortcut.keys)
            #expect(!alternatives.isEmpty, "\(shortcut.id)")
            #expect(alternatives.map { $0.joined() }.joined(separator: " / ") == shortcut.keys, "\(shortcut.id)")
        }
    }
}
