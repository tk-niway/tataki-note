import AppKit
import Testing
@testable import TatakiNote

struct FieldEditKeyTests {
    // MARK: - 欄の編集のキー

    @Test("AC-9: ⌘X・⌘C・⌘V・⌘A・⌘Z・⇧⌘Z は編集の操作になり、それ以外のキーはならない")
    func fieldEditKeys() {
        #expect(FieldEditKey.action(modifiers: [.command], character: "x") == .cut)
        #expect(FieldEditKey.action(modifiers: [.command], character: "c") == .copy)
        #expect(FieldEditKey.action(modifiers: [.command], character: "v") == .paste)
        #expect(FieldEditKey.action(modifiers: [.command], character: "a") == .selectAll)
        #expect(FieldEditKey.action(modifiers: [.command], character: "z") == .undo)
        #expect(FieldEditKey.action(modifiers: [.command, .shift], character: "z") == .redo)
        #expect(FieldEditKey.action(modifiers: [.command, .capsLock], character: "v") == .paste)

        #expect(FieldEditKey.action(modifiers: [.command], character: "l") == nil)
        #expect(FieldEditKey.action(modifiers: [.command], character: "d") == nil)
        #expect(FieldEditKey.action(modifiers: [.command], character: "s") == nil)
        #expect(FieldEditKey.action(modifiers: [.command, .shift], character: "s") == nil)
        #expect(FieldEditKey.action(modifiers: [.command], character: "w") == nil)
        #expect(FieldEditKey.action(modifiers: [.command], character: "q") == nil)
        #expect(FieldEditKey.action(modifiers: [.command, .option], character: "v") == nil)
        #expect(FieldEditKey.action(modifiers: [], character: "v") == nil)
    }
}
