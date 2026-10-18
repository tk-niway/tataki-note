import SwiftUI

/// 保存の結果を知らせる、丸いカプセルのトースト。
struct PanelToastView: View {
    let message: String
    var style: PanelToastStyle = .done

    private enum Stage {
        case entering
        case shown
        case leaving
    }

    private static let transitionSeconds = 0.2

    @Environment(\.isAppAnimationReduced) private var reduceMotion
    @State private var stage: Stage = .entering

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style == .notice ? "exclamationmark" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(style == .notice ? Color.orange : Color.accentColor))
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .background(Capsule().fill(Color.primary.opacity(0.88)))
        .shadow(color: .black.opacity(0.3), radius: 13, y: 10)
        .opacity(stage == .shown ? 1 : 0)
        .offset(y: stage == .entering ? 10 : 0)
        .onAppear {
            if reduceMotion {
                stage = .shown
            } else {
                withAnimation(.easeOut(duration: Self.transitionSeconds)) {
                    stage = .shown
                }
            }
        }
        .task {
            try? await Task.sleep(for: SaveAnimationModel.toastDuration - .milliseconds(200))
            if reduceMotion {
                stage = .leaving
            } else {
                withAnimation(.easeIn(duration: Self.transitionSeconds)) {
                    stage = .leaving
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}
