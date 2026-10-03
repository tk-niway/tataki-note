import SwiftUI

/// 設定ウィンドウの右側(「一般」「キー」「パネル」「アプリ情報」)の余白。
enum SettingsDetailLayout {
    static let leading: CGFloat = 20
    static let trailing: CGFloat = 36
    static let top: CGFloat = 16
    static let bottom: CGFloat = 20
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
