import SwiftUI

/// キーボードのキー1つの見た目。
struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .separatorColor))
                        .offset(y: 1.5)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .padding(.bottom, 1.5)
    }
}

/// キーの組を並べる。組の間に薄い「/」を置く。
struct KeyCapRow: View {
    let alternatives: [[String]]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, caps in
                if index > 0 {
                    Text(verbatim: "/")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 3) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapView(text: cap)
                    }
                }
            }
        }
    }
}
