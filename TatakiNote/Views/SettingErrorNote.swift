import SwiftUI

/// 設定画面の項目の下に置く、赤い印つきの注意(11pt)。
struct SettingErrorNote: View {
    private let text: Text
    private let identifier: String

    /// 訳す文の鍵から作る。
    init(text: LocalizedStringKey, identifier: String) {
        self.text = Text(text)
        self.identifier = identifier
    }

    /// 訳し終えた文から作る。
    init(_ text: String, identifier: String) {
        self.text = Text(text)
        self.identifier = identifier
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
