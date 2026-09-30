import SwiftUI

/// @note p0-694
enum SettingsDetailLayout {
    static let leading: CGFloat = 20
    /// @note p0-695
    static let trailing: CGFloat = 36
    static let top: CGFloat = 16
    static let bottom: CGFloat = 20
}

extension View {
    /// @note p0-696
    func settingsDetailPadding() -> some View {
        padding(.leading, SettingsDetailLayout.leading)
            .padding(.trailing, SettingsDetailLayout.trailing)
            .padding(.top, SettingsDetailLayout.top)
            .padding(.bottom, SettingsDetailLayout.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
