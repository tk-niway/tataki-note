import SwiftUI

/// 設定ウィンドウの右側(「一般」「ホットキーとキー操作」「パネル」「情報」)の余白。
enum SettingsDetailLayout {
    static let leading: CGFloat = 28
    static let trailing: CGFloat = 28
    static let top: CGFloat = 8
    static let bottom: CGFloat = 28
    static let headerTop: CGFloat = 18
    static let headerBottom: CGFloat = 6
}

extension View {
    func settingsDetailPadding() -> some View {
        padding(.leading, SettingsDetailLayout.leading)
            .padding(.trailing, SettingsDetailLayout.trailing)
            .padding(.top, SettingsDetailLayout.top)
            .padding(.bottom, SettingsDetailLayout.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
