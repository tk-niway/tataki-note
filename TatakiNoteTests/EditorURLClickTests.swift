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

    private var pointingAreas: [EditorURLHitArea] {
        [EditorURLHitArea(url: first, rects: [CGRect(x: 10, y: 0, width: 100, height: 20)], isFolded: true)]
    }

    private let visible = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test("AC-27: ⌘ だけ(capsLock・function は無視)で URL の上なら指にする")
    func showsPointingHandOnURLWithCommand() {
        let point = CGPoint(x: 50, y: 10)
        #expect(EditorURLClick.showsPointingHand(at: point, modifiers: .command, in: pointingAreas, visibleRect: visible))
        #expect(EditorURLClick.showsPointingHand(at: point, modifiers: [.command, .capsLock], in: pointingAreas, visibleRect: visible))
        #expect(EditorURLClick.showsPointingHand(at: point, modifiers: [.command, .function], in: pointingAreas, visibleRect: visible))
    }

    @Test("AC-27: 修飾キーなし・⌘ 以外の組み合わせでは指にしない")
    func hidesPointingHandForOtherModifiers() {
        let point = CGPoint(x: 50, y: 10)
        for modifiers: NSEvent.ModifierFlags in [[], .shift, .option, .control, [.command, .shift], [.command, .option], [.command, .control]] {
            #expect(!EditorURLClick.showsPointingHand(at: point, modifiers: modifiers, in: pointingAreas, visibleRect: visible))
        }
    }

    @Test("AC-27: URL の外・見えている範囲の外・URL が無いときは指にしない")
    func hidesPointingHandOutsideURL() {
        #expect(!EditorURLClick.showsPointingHand(at: CGPoint(x: 200, y: 10), modifiers: .command, in: pointingAreas, visibleRect: visible))
        #expect(!EditorURLClick.showsPointingHand(
            at: CGPoint(x: 50, y: 10), modifiers: .command, in: pointingAreas,
            visibleRect: CGRect(x: 0, y: 100, width: 400, height: 300)
        ))
        #expect(!EditorURLClick.showsPointingHand(at: CGPoint(x: 50, y: 10), modifiers: .command, in: [], visibleRect: visible))
    }
}
