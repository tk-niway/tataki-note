import AppKit

extension KeyCode {
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}

/// @note p0-396
enum PanelShortcutRecorderInput {
    enum Action: Equatable {
        /// @note p0-397
        case cancel
        /// @note p0-398
        case clear
        /// @note p0-399
        case record
    }

    /// @note p0-400
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action {
        let relevantModifiers = modifiers.intersection(PanelShortcut.relevantModifiers)
        guard relevantModifiers.isEmpty else { return .record }
        switch keyCode {
        case KeyCode.escape: return .cancel
        case KeyCode.delete, KeyCode.forwardDelete: return .clear
        default: return .record
        }
    }

    /// @note p0-401
    static func isOutsideClick(location: CGPoint, recorderBounds: CGRect, isSameWindow: Bool) -> Bool {
        guard isSameWindow else { return true }
        return !recorderBounds.insetBy(dx: -2, dy: -2).contains(location)
    }
}
