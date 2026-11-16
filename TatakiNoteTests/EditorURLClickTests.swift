import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct EditorURLClickTests {
    private let first = EditorURL(range: NSRange(location: 0, length: 20), text: "https://example.com/a")
    private let second = EditorURL(range: NSRange(location: 30, length: 20), text: "https://example.com/b")

    @Test("AC-18: ⌘ だけを押したクリックは URL を開く")
    func commandOnlyOpens() {
        #expect(EditorURLClick.opensURL(modifiers: .command))
    }

    @Test("AC-18: capsLock・function・numericPad は無視して ⌘ だけなら開く")
    func ignoresPassiveModifiers() {
        #expect(EditorURLClick.opensURL(modifiers: [.command, .capsLock]))
        #expect(EditorURLClick.opensURL(modifiers: [.command, .function]))
        #expect(EditorURLClick.opensURL(modifiers: [.command, .numericPad]))
    }

    @Test("AC-18: 修飾キーなし・⌘ 以外・⌘ と他の組み合わせでは開かない")
    func otherModifiersDoNotOpen() {
        #expect(!EditorURLClick.opensURL(modifiers: []))
        #expect(!EditorURLClick.opensURL(modifiers: .shift))
        #expect(!EditorURLClick.opensURL(modifiers: .option))
        #expect(!EditorURLClick.opensURL(modifiers: .control))
        #expect(!EditorURLClick.opensURL(modifiers: [.command, .shift]))
        #expect(!EditorURLClick.opensURL(modifiers: [.command, .option]))
        #expect(!EditorURLClick.opensURL(modifiers: [.command, .control]))
        #expect(!EditorURLClick.opensURL(modifiers: .capsLock))
    }

    @Test("AC-19: 点を含む矩形を持つ URL を返し、外なら nil")
    func findsURLAtPoint() {
        let areas = [
            EditorURLHitArea(url: first, rects: [CGRect(x: 10, y: 10, width: 50, height: 20)], isFolded: true),
            EditorURLHitArea(
                url: second,
                rects: [CGRect(x: 10, y: 40, width: 50, height: 20), CGRect(x: 0, y: 60, width: 30, height: 20)],
                isFolded: false
            )
        ]
        #expect(EditorURLClick.url(at: CGPoint(x: 20, y: 15), in: areas) == first)
        #expect(EditorURLClick.url(at: CGPoint(x: 20, y: 45), in: areas) == second)
        #expect(EditorURLClick.url(at: CGPoint(x: 10, y: 65), in: areas) == second)
        #expect(EditorURLClick.url(at: CGPoint(x: 200, y: 15), in: areas) == nil)
        #expect(EditorURLClick.url(at: CGPoint(x: 20, y: 35), in: areas) == nil)
        #expect(EditorURLClick.url(at: CGPoint(x: 20, y: 15), in: []) == nil)
    }
}
