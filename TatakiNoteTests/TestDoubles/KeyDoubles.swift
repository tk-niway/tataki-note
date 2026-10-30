import Foundation
@testable import TatakiNote

@MainActor
final class FakeHotkeyController {
    var hotkey: PanelShortcut?
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    init(hotkey: PanelShortcut? = nil) {
        self.hotkey = hotkey
    }

    func currentHotkey() -> PanelShortcut? { hotkey }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func set(_ shortcut: PanelShortcut?) {
        hotkey = shortcut
        setCalls.append(shortcut)
    }

    private(set) var setCalls: [PanelShortcut?] = []
}
