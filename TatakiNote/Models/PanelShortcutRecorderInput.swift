import AppKit

extension KeyCode {
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}

/// 記録ボックスで押されたキー・クリックの位置から、どう振る舞うかを決める。
enum PanelShortcutRecorderInput {
    enum Action: Equatable {
        case cancel
        case clear
        case record
    }

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action {
        let relevantModifiers = modifiers.intersection(PanelShortcut.relevantModifiers)
        guard relevantModifiers.isEmpty else { return .record }
        switch keyCode {
        case KeyCode.escape: return .cancel
        case KeyCode.delete, KeyCode.forwardDelete: return .clear
        default: return .record
        }
    }

    static func isOutsideClick(location: CGPoint, recorderBounds: CGRect, isSameWindow: Bool) -> Bool {
        guard isSameWindow else { return true }
        return !recorderBounds.insetBy(dx: -2, dy: -2).contains(location)
    }
}
