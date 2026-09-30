/// @note p0-312
enum PanelActionKey: String, CaseIterable, Sendable {
    case shiftEnter
    case commandEnter
    case commandShiftEnter
    /// @note p0-313
    case none

    /// @note p0-314
    var shortcut: PanelShortcut? {
        switch self {
        case .shiftEnter: .shiftReturn
        case .commandEnter: .commandReturn
        case .commandShiftEnter: .commandShiftReturn
        case .none: nil
        }
    }
}
