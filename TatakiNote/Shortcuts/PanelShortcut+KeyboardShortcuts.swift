import AppKit
import KeyboardShortcuts

extension PanelShortcut {
    /// @note p0-543
    var displayText: String {
        KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: Int(keyCode)), modifiers: modifiers).description
    }

    /// @note p0-544
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(keyCode: UInt16(clamping: shortcut.carbonKeyCode), modifiers: shortcut.modifiers)
    }

    /// @note p0-545
    static func currentHotkey() -> PanelShortcut? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) else { return nil }
        return PanelShortcut(shortcut)
    }

    /// @note p0-546
    static func pauseHotkey() {
        KeyboardShortcuts.disable(.togglePanel)
    }

    /// @note p0-547
    static func resumeHotkey() {
        KeyboardShortcuts.enable(.togglePanel)
    }
}
