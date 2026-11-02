import AppKit
import SwiftUI

/// タイトルバーの右端に出す、挿入先のアプリの表示。挿入先が無いときは「挿入先なし」を出す。押すとノートに切り替える。
struct InsertionTargetView: View {
    let target: InsertionTarget?
    let noTargetAlertCount: Int
    let isPending: Bool
    let appIcon: @MainActor (InsertionTarget) -> NSImage
    let onSwitchToNote: () -> Void

    @Environment(\.isAppAnimationReduced) private var reduceMotion

    private static let iconSize: CGFloat = 16
    private static let hitInset: CGFloat = 4
    private static let hitHeight: CGFloat = 22

    init(
        target: InsertionTarget?,
        noTargetAlertCount: Int = 0,
        isPending: Bool = false,
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = InsertionTargetBadge.systemIcon(for:),
        onSwitchToNote: @escaping () -> Void = {}
    ) {
        self.target = target
        self.noTargetAlertCount = noTargetAlertCount
        self.isPending = isPending
        self.appIcon = appIcon
        self.onSwitchToNote = onSwitchToNote
    }

    var body: some View {
        let display = InsertionTargetBadge.display(target: target, isPending: isPending)
        Button(action: onSwitchToNote) {
            content(for: display)
                .padding(.horizontal, Self.hitInset)
                .frame(height: Self.hitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(InsertionTargetButtonStyle())
        .focusable(false)
        .padding(.horizontal, -Self.hitInset)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityHint(DraftMode.insert.titleBarTrailingAccessibilityHint)
        .accessibilityIdentifier(display.accessibilityIdentifier)
    }

    @ViewBuilder
    private func content(for display: InsertionTargetDisplay) -> some View {
        switch display {
        case .target(let badge):
            targetBody(badge)
        case .pending, .noTarget:
            noTargetBody
                .opacity(display.isNoTargetLabelVisible ? 1 : 0)
                .overlay(alignment: .trailing) {
                    if display == .pending {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
        }
    }

    private func targetBody(_ badge: InsertionTargetBadge) -> some View {
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
        }
    }

    // MARK: - 挿入先なし

    private struct AlertValues {
        var offsetX: CGFloat = 0
        var alert: Double = 0
    }

    private var noTargetBody: some View {
        let offsets = InsertionTargetBadge.noTargetShakeOffsets(isAnimationEnabled: !reduceMotion)
        return Text(verbatim: InsertionTargetBadge.noTargetLabel)
            .font(.system(size: 11))
            .keyframeAnimator(initialValue: AlertValues(), trigger: noTargetAlertCount) { content, value in
                content
                    .foregroundStyle(value.alert > 0 ? Color.orange : Color.secondary)
                    .offset(x: value.offsetX)
            } keyframes: { _ in
                KeyframeTrack(\.offsetX) {
                    LinearKeyframe(offsets[0], duration: 0.075)
                    LinearKeyframe(offsets[1], duration: 0.075)
                    LinearKeyframe(offsets[2], duration: 0.075)
                    LinearKeyframe(offsets[3], duration: 0.075)
                    LinearKeyframe(offsets[4], duration: 0.075)
                    LinearKeyframe(offsets[5], duration: 0.075)
                }
                KeyframeTrack(\.alert) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 0.45)
                    MoveKeyframe(0)
                }
            }
    }
}

private struct InsertionTargetButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(backgroundOpacity(isPressed: configuration.isPressed)))
            }
            .onHover { isHovering = $0 }
    }

    private func backgroundOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.24 }
        return isHovering ? 0.14 : 0
    }
}
