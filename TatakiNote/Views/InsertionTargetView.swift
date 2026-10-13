import AppKit
import SwiftUI

/// タイトルバーの右端に出す、挿入先のアプリの表示。挿入先が無いときは「挿入先なし」を出す。
struct InsertionTargetView: View {
    let target: InsertionTarget?
    let noTargetAlertCount: Int
    let appIcon: @MainActor (InsertionTarget) -> NSImage

    @State private var isHovering = false

    private static let iconSize: CGFloat = 16
    private static let noTargetTipWidth: CGFloat = 260

    init(
        target: InsertionTarget?,
        noTargetAlertCount: Int = 0,
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = InsertionTargetBadge.systemIcon(for:)
    ) {
        self.target = target
        self.noTargetAlertCount = noTargetAlertCount
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
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.14))
                    )
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
        } else {
            noTargetBody
        }
    }

    // MARK: - 挿入先なし

    private struct AlertValues {
        var offsetX: CGFloat = 0
        var alert: Double = 0
    }

    private var noTargetBody: some View {
        Text(verbatim: InsertionTargetBadge.noTargetLabel)
            .font(.system(size: 11))
            .keyframeAnimator(initialValue: AlertValues(), trigger: noTargetAlertCount) { content, value in
                content
                    .foregroundStyle(value.alert > 0 ? Color.orange : Color.secondary)
                    .offset(x: value.offsetX)
            } keyframes: { _ in
                KeyframeTrack(\.offsetX) {
                    LinearKeyframe(-4, duration: 0.075)
                    LinearKeyframe(4, duration: 0.075)
                    LinearKeyframe(-4, duration: 0.075)
                    LinearKeyframe(4, duration: 0.075)
                    LinearKeyframe(-2, duration: 0.075)
                    LinearKeyframe(0, duration: 0.075)
                }
                KeyframeTrack(\.alert) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 0.45)
                    MoveKeyframe(0)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InsertionTargetBadge.noTargetLabel)
            .accessibilityIdentifier("promptPanel.noInsertionTarget")
            .overlay(alignment: .bottomTrailing) {
                if isHovering {
                    wrappedTip(InsertionTargetBadge.noTargetTipText)
                        .alignmentGuide(.bottom) { $0[.top] - 8 }
                }
            }
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    // MARK: - チップ

    private func tip(_ text: String) -> some View {
        tipChrome(Text(verbatim: text).fixedSize())
    }

    private func wrappedTip(_ text: String) -> some View {
        tipChrome(
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Self.noTargetTipWidth, alignment: .leading)
        )
    }

    private func tipChrome<Content: View>(_ content: Content) -> some View {
        content
            .font(.system(size: 11))
            .foregroundStyle(.primary)
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
