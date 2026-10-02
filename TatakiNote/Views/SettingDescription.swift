import SwiftUI

/// 設定画面の項目の下に置く説明文(11pt・secondary・縦に伸びて折り返す)。
struct SettingDescription: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
