import AppKit

/// 設定画面・権限の案内・パネルの窓の外観(テーマ)。
enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    static let defaultValue: AppTheme = .system

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
