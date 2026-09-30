import AppKit

/// @note p0-179
enum AppTheme: String, CaseIterable, Sendable {
    /// @note p0-180
    case system
    /// @note p0-181
    case light
    /// @note p0-182
    case dark

    static let defaultValue: AppTheme = .system

    /// @note p0-183
    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            nil
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }
}
