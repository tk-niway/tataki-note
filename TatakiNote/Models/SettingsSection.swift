/// @note p0-459
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    /// @note p0-460
    case general
    /// @note p0-461
    case editor
    /// @note p0-462
    case appInfo

    var id: Self { self }
}
