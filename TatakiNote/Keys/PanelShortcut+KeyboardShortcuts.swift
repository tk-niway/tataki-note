import AppKit
import KeyboardShortcuts

extension PanelShortcut {
    var displayText: String {
        KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: Int(keyCode)), modifiers: modifiers).description
    }

    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(keyCode: UInt16(clamping: shortcut.carbonKeyCode), modifiers: shortcut.modifiers)
    }

    static func currentHotkey() -> PanelShortcut? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) else { return nil }
        return PanelShortcut(shortcut)
    }

    static func setHotkey(_ shortcut: PanelShortcut?) {
        KeyboardShortcuts.setShortcut(
            shortcut.map { KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: Int($0.keyCode)), modifiers: $0.modifiers) },
            for: .togglePanel
        )
    }

    static func pauseHotkey() {
        KeyboardShortcuts.disable(.togglePanel)
    }

    static func resumeHotkey() {
        KeyboardShortcuts.enable(.togglePanel)
    }
}
