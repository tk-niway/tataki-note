import SwiftUI

/// 挿入できなかったことを知らせる吹き出しの中身。
struct InsertionFailureBubbleView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
