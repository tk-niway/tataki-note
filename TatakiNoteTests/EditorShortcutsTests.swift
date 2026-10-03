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

    @Test("AC-8: 「ショートカットキー」の説明文は、割り当ては変えられないことと、確定のキーは同じ「キー」の「確定キー」「確定+送信キー」で確かめられることを書き、「一般」「エディタ設定」を書かない")
    func settingDescriptionPointsToKeysInSameSection() {
        let description = EditorShortcuts.settingDescription

        for phrase in ["割り当ては変えられません", "確定キー", "確定+送信キー"] {
            #expect(description.contains(phrase), "\(phrase)")
        }
        for phrase in ["一般", "エディタ設定"] {
            #expect(!description.contains(phrase), "\(phrase)")
        }
    }
}
