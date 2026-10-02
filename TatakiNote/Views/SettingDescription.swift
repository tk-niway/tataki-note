import SwiftUI

/// 設定画面の項目の下に置く説明文(11pt・secondary・縦に伸びて折り返す)。
struct SettingDescription: View {
    private let text: Text

    /// 訳す文の鍵から作る。
    init(text: LocalizedStringKey) {
        self.text = Text(text)
    }

    /// 訳し終えた文から作る。
    init(_ text: String) {
        self.text = Text(text)
    }

    var body: some View {
        text
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
