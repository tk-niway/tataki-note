import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct KeyEventPairTests {
    @Test("AC-6: 送信のキーは Return(36)・修飾キーなしの、押すと離すの1組になる")
    func submitKeyEventsAreReturnWithoutModifiers() throws {
        let events = try #require(CGEventSubmitKeyPoster.makeEvents())

        #expect(events.keyDown.getIntegerValueField(.keyboardEventKeycode) == 36)
        #expect(events.keyUp.getIntegerValueField(.keyboardEventKeycode) == 36)
        #expect(events.keyDown.type == .keyDown)
        #expect(events.keyUp.type == .keyUp)
        #expect(events.keyDown.flags.intersection(.maskCommand).isEmpty)
        #expect(events.keyUp.flags.intersection(.maskCommand).isEmpty)
    }

    @Test("AC-6: 貼り付けのキーは V(9)・⌘ の、押すと離すの1組になる")
    func pasteShortcutEventsAreVWithCommand() throws {
        let pair = try #require(KeyEventPair(keyCode: 9, flags: .maskCommand))

        #expect(pair.keyDown.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(pair.keyUp.getIntegerValueField(.keyboardEventKeycode) == 9)
        #expect(pair.keyDown.type == .keyDown)
        #expect(pair.keyUp.type == .keyUp)
        #expect(pair.keyDown.flags.contains(.maskCommand))
        #expect(pair.keyUp.flags.contains(.maskCommand))
    }

    @Test("AC-6: 修飾キーなしで作ったイベントには ⌘ が付かない")
    func eventsWithoutFlagsCarryNoCommand() throws {
        let pair = try #require(KeyEventPair(keyCode: 36, flags: []))

        #expect(!pair.keyDown.flags.contains(.maskCommand))
        #expect(!pair.keyUp.flags.contains(.maskCommand))
    }
}
