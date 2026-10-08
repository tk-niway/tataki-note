import SwiftUI

/// 保存していない文章があるまま切り替えるときに、本文の上に重ねる確認。
struct PanelConfirmationOverlay: View {
    let onResolve: (UnsavedTextChoice) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static let cardMaximumWidth: CGFloat = 360
    private static let cardMargin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                (colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.6))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    card(showsDecorations: true)
                    card(showsDecorations: false)
                }
                .frame(width: min(Self.cardMaximumWidth, max(proxy.size.width - Self.cardMargin * 2, 0)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptPanel.confirmation")
    }

    private func card(showsDecorations: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if showsDecorations {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.yellow)
                }
                Text("保存していない文章があります。下書きに保存しますか?")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                choiceButton("保存しない", key: "⌘D", identifier: "discard", choice: .discard, showsKey: showsDecorations)
                Spacer(minLength: 0)
                choiceButton("キャンセル", key: "esc", identifier: "cancel", choice: .cancel, showsKey: showsDecorations)
                choiceButton("保存", key: "↩", identifier: "save", choice: .save, showsKey: showsDecorations)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    private func choiceButton(
        _ title: String,
        key: String,
        identifier: String,
        choice: UnsavedTextChoice,
        showsKey: Bool
    ) -> some View {
        Button {
            onResolve(choice)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                if showsKey {
                    Text(verbatim: key)
                        .font(.system(size: 10))
                        .opacity(0.7)
                }
            }
        }
        .focusable(false)
        .accessibilityIdentifier("promptPanel.confirmation.\(identifier)")
    }
}
