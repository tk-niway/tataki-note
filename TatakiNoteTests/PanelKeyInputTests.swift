import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelKeyInputTests {
    private static func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        charactersIgnoringModifiers: String
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @Test("AC-7: キーコードはそのまま、文字は修飾キーを除いた文字の小文字になる")
    func keyCodeAndCharactersAreTaken() throws {
        let event = try Self.keyEvent(keyCode: 40, modifiers: [.command, .shift], characters: "K", charactersIgnoringModifiers: "K")
        let input = PanelKeyInput(event: event, hasMarkedText: false)
        #expect(input.keyCode == 40)
        #expect(input.characters == "k")
        #expect(input.modifiers == [.shift, .command])
    }

    @Test("AC-7: テンキーの Enter のキーコードは 76 のまま")
    func keypadEnterKeyCodeIsKept() throws {
        let event = try Self.keyEvent(keyCode: KeyCode.keypadEnter, modifiers: [.command, .numericPad], characters: "\r", charactersIgnoringModifiers: "\r")
        let input = PanelKeyInput(event: event, hasMarkedText: false)
        #expect(input.keyCode == KeyCode.keypadEnter)
    }

    @Test("AC-7: Caps Lock は修飾キーに残り、機器ごとの印は落ちる")
    func capsLockIsKeptAndDeviceDependentBitsAreDropped() throws {
        let deviceDependent = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags([.command, .capsLock]).rawValue | 0x8)
        let event = try Self.keyEvent(keyCode: 1, modifiers: deviceDependent, characters: "s", charactersIgnoringModifiers: "s")
        let input = PanelKeyInput(event: event, hasMarkedText: false)
        #expect(input.modifiers == [.command, .capsLock])
        #expect(input.modifiers.rawValue & 0x8 == 0)
    }

    @Test("AC-7: 文字が空なら空、変換中かは渡した値になる")
    func emptyCharactersAndMarkedTextFlag() throws {
        let event = try Self.keyEvent(keyCode: 36, modifiers: [], characters: "", charactersIgnoringModifiers: "")
        #expect(PanelKeyInput(event: event, hasMarkedText: false).characters == "")
        #expect(PanelKeyInput(event: event, hasMarkedText: false).hasMarkedText == false)
        #expect(PanelKeyInput(event: event, hasMarkedText: true).hasMarkedText == true)
    }
}
