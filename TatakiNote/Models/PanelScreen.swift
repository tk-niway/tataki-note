/// @note p0-377
enum PanelScreen: String, CaseIterable, Sendable {
    /// @note p0-378
    case nearFocusedField
    /// @note p0-379
    case targetWindow
    /// @note p0-380
    case mouse
    /// @note p0-381
    case main

    static let defaultValue: PanelScreen = .nearFocusedField

    /// @note p0-382
    var usesTargetWindowFrame: Bool {
        self == .targetWindow || self == .nearFocusedField
    }
}
