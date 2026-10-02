import Testing
@testable import TatakiNote

@MainActor
struct EditorShortcutsTests {
    @Test("AC-7: ショートカットキーの一覧は7行で、行の入れ替え・複製・行ごとのコピー・切り取り・貼り付け・行と単語の選択のキーがあり、改行・閉じる・確定・確定+送信のキーは入らない")
    func listsEditingShortcuts() {
        let shortcuts = EditorShortcuts.all

        #expect(shortcuts.count == 7)
        #expect(Set(shortcuts.map(\.id)).count == 7)
        for keys in ["⌥↑", "⌥↓", "⇧⌥↑", "⇧⌥↓", "⌘C", "⌘X", "⌘V", "⌘L", "⌘D"] {
            #expect(shortcuts.contains { $0.keys.contains(keys) }, "\(keys)")
        }
        #expect(shortcuts.allSatisfy { !$0.keys.isEmpty && !$0.action.isEmpty })

        for keys in ["↩", "esc", "⌘↩", "⇧⌘↩"] {
            #expect(!shortcuts.contains { $0.keys.contains(keys) }, "\(keys)")
        }
    }
}
