import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // @note p0-548
    static let togglePanel = Self("togglePanel", initial: .init(.space, modifiers: [.option, .shift]))
}
