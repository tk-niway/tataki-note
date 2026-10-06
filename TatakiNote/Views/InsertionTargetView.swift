import AppKit
import SwiftUI

/// タイトルバーの右端に出す、挿入先のアプリの表示。
struct InsertionTargetView: View {
    let target: InsertionTarget?
    let appIcon: @MainActor (InsertionTarget) -> NSImage

    @State private var isHovering = false

    private static let iconSize: CGFloat = 16

    init(
        target: InsertionTarget?,
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = InsertionTargetBadge.systemIcon(for:)
    ) {
        self.target = target
        self.appIcon = appIcon
    }

    var body: some View {
        if let badge = InsertionTargetBadge.make(for: target) {
            HStack(spacing: 4) {
                Text(verbatim: InsertionTargetBadge.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Image(nsImage: appIcon(badge.target))
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .contentShape(Rectangle())
                    .onHover { isHovering = $0 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badge.accessibilityLabel)
            .accessibilityIdentifier("promptPanel.insertionTarget")
            .overlay(alignment: .bottomTrailing) {
                if isHovering {
                    tip(badge.tipText)
                        .alignmentGuide(.bottom) { $0[.top] - 8 }
                }
            }
            .animation(.easeOut(duration: 0.1), value: isHovering)
        }
    }

    private func tip(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier("promptPanel.insertionTargetTip")
            .transition(.opacity)
    }
}
