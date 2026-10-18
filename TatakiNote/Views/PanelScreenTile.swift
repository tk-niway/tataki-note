import SwiftUI

/// パネルを出す位置を選ぶ、ミニ画面の図つきのタイル。
struct PanelScreenTile: View {
    let screen: PanelScreen
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    @Environment(\.isAppAnimationReduced) private var reduceMotion

    private static let screenHeight: CGFloat = 56
    private static let panelSize = CGSize(width: 24, height: 15)

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                miniScreen
                Text(screen.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
            .padding(.top, 7)
            .padding(.horizontal, 7)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.17) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(screen.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.panelScreen.\(screen.rawValue)")
    }

    private var miniScreen: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.1))
                marker(in: proxy.size)
                panel(in: proxy.size)
            }
        }
        .frame(height: Self.screenHeight)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func marker(in size: CGSize) -> some View {
        let tint = Color.secondary.opacity(0.6)
        switch screen {
        case .nearFocusedField:
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(width: size.width * 0.56, height: 5)
                .offset(x: size.width * 0.14, y: size.height * 0.72)
        case .targetWindow:
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(tint, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: size.width * 0.76, height: size.height * 0.72)
                .offset(x: size.width * 0.12, y: size.height * 0.14)
        case .mouse:
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .offset(x: size.width * 0.6, y: size.height * 0.18)
        case .main:
            Rectangle()
                .fill(tint)
                .frame(width: size.width, height: 5)
        }
    }

    private func panel(in size: CGSize) -> some View {
        let origin = panelOrigin(in: size)
        return RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.6))
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .scaleEffect(isSelected ? 1 : 0.82)
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: isSelected)
            .offset(x: origin.x, y: origin.y)
    }

    private func panelOrigin(in size: CGSize) -> CGPoint {
        switch screen {
        case .nearFocusedField:
            CGPoint(x: size.width * 0.16, y: size.height * 0.72 - 20)
        case .targetWindow:
            CGPoint(x: size.width / 2 - Self.panelSize.width / 2, y: 20)
        case .mouse:
            CGPoint(x: size.width * 0.6 - 6, y: size.height * 0.18 + 11)
        case .main:
            CGPoint(x: size.width / 2 - Self.panelSize.width / 2, y: 22)
        }
    }
}
