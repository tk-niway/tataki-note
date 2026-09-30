/// @note p0-235
enum AutoShowMode: String, CaseIterable, Sendable {
    /// @note p0-236
    case off
    /// @note p0-237
    case allApps
    /// @note p0-238
    case selectedApps

    static let defaultValue: AutoShowMode = .off
}
