import AppKit
import SwiftUI

/// 今の書体・文字サイズ・透明度で、パネルの入力欄の見た目を示すプレビュー。
struct PanelTextPreview: View {
    let font: NSFont
    let opacity: Double
    let accessibilityValue: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 104

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StripeBackground()
                previewBox
                    .frame(width: proxy.size.width * 0.62)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("プレビュー")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("settings.panelPreview")
    }

    private var previewBox: some View {
        HStack(alignment: .center, spacing: 2) {
            Text(PanelView.placeholderText)
                .font(Font(font))
                .lineLimit(1)
            BlinkingCaret(height: font.pointSize * 1.2, isBlinking: !reduceMotion)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .opacity(opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: font.pointSize)
    }
}

private struct StripeBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 12
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(Color.primary.opacity(0.05)), lineWidth: 6)
        }
    }
}

private struct BlinkingCaret: View {
    let height: CGFloat
    let isBlinking: Bool

    var body: some View {
        if isBlinking {
            caret.phaseAnimator([true, false]) { content, isVisible in
                content.opacity(isVisible ? 1 : 0)
            } animation: { _ in
                .linear(duration: 0.05).delay(0.5)
            }
        } else {
            caret
        }
    }

    private var caret: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 1.5, height: height)
    }
}
