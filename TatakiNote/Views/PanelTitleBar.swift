import AppKit
import SwiftUI

/// パネルの上部に重ねる、閉じる・開閉・新規作成・保存・挿入先のバー。
struct PanelTitleBar: View {
    let target: InsertionTarget?
    let noTargetAlertCount: Int
    let session: DraftSession?
    let isSidebarOpen: Bool
    let onClose: () -> Void
    let onToggleSidebar: () -> Void
    let onNewDraft: () -> Void
    let onSaveDraft: () -> Void
    let appIcon: @MainActor (InsertionTarget) -> NSImage
    let saveAnimation: SaveAnimationModel?
    let showsInsertionTarget: Bool

    init(
        target: InsertionTarget?,
        showsInsertionTarget: Bool = true,
        noTargetAlertCount: Int = 0,
        session: DraftSession? = nil,
        saveAnimation: SaveAnimationModel? = nil,
        isSidebarOpen: Bool = false,
        onClose: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void = {},
        onNewDraft: @escaping () -> Void = {},
        onSaveDraft: @escaping () -> Void = {},
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = InsertionTargetBadge.systemIcon(for:)
    ) {
        self.target = target
        self.showsInsertionTarget = showsInsertionTarget
        self.noTargetAlertCount = noTargetAlertCount
        self.session = session
        self.saveAnimation = saveAnimation
        self.isSidebarOpen = isSidebarOpen
        self.onClose = onClose
        self.onToggleSidebar = onToggleSidebar
        self.onNewDraft = onNewDraft
        self.onSaveDraft = onSaveDraft
        self.appIcon = appIcon
    }

    private static let hitSize: CGFloat = 20
    private static let iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            closeButton
            sidebarToggleButton
                .padding(.leading, 4)
            Spacer(minLength: 0)
            newDraftButton
            saveDraftButton
                .padding(.leading, 4)
            if showsInsertionTarget {
                InsertionTargetView(target: target, noTargetAlertCount: noTargetAlertCount, appIcon: appIcon)
                    .padding(.leading, 10)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.titleBarHeight)
    }

    // MARK: - ボタン

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: Self.iconSize))
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(CloseButtonStyle())
        .focusable(false)
        .help("閉じる(書いた文章は残ります)")
        .accessibilityLabel("閉じる")
        .accessibilityIdentifier("promptPanel.closeButton")
    }

    private var sidebarToggleButton: some View {
        Button(action: onToggleSidebar) {
            iconLabel("sidebar.left")
                .keyframeAnimator(initialValue: 1.0, trigger: saveAnimation?.absorbCount ?? 0) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(1.0, duration: 0.001)
                        CubicKeyframe(1.2, duration: SaveAnimationModel.absorbingDuration.seconds / 2)
                        CubicKeyframe(1.0, duration: SaveAnimationModel.absorbingDuration.seconds / 2)
                    }
                }
                .anchorPreference(key: SidebarToggleAnchorKey.self, value: .bounds) { $0 }
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .help("下書きと履歴(⌘B で開閉、⌘K で検索)")
        .accessibilityLabel("サイドバー")
        .accessibilityValue(isSidebarOpen ? "開いています" : "閉じています")
        .accessibilityIdentifier("promptPanel.sidebarToggle")
    }

    private var newDraftButton: some View {
        Button(action: onNewDraft) {
            iconLabel("square.and.pencil")
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .disabled(!(session?.isNewDraftAvailable ?? false) || session?.pendingSwitch != nil)
        .help("新しい書きかけ(⌘N)")
        .accessibilityLabel("新しい書きかけ")
        .accessibilityIdentifier("promptPanel.newDraftButton")
    }

    private var saveDraftButton: some View {
        let isConfirming = saveAnimation?.isShowingSaveConfirmation ?? false
        return Button(action: onSaveDraft) {
            ZStack {
                iconLabel("square.and.arrow.down")
                    .opacity(isConfirming ? 0 : 1)
                Image(systemName: "checkmark")
                    .font(.system(size: Self.iconSize, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: Self.hitSize, height: Self.hitSize)
                    .opacity(isConfirming ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.1), value: isConfirming)
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .disabled(!(session?.isSaveAvailable ?? false) || session?.pendingSwitch != nil)
        .help("下書きに保存(⌘S)")
        .accessibilityLabel("下書きに保存")
        .accessibilityIdentifier("promptPanel.saveDraftButton")
    }

    private func iconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Self.iconSize))
            .frame(width: Self.hitSize, height: Self.hitSize)
            .contentShape(Rectangle())
    }

    // MARK: - スタイル

    private struct CloseButtonStyle: ButtonStyle {
        @State private var isHovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(configuration.isPressed ? .primary : (isHovering ? .secondary : .tertiary))
                .onHover { isHovering = $0 }
        }
    }

}

/// パネルのアイコンのボタンの見た目。押している間だけ濃くする。
struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
    }

    private func foreground(isPressed: Bool) -> HierarchicalShapeStyle {
        if !isEnabled { return .tertiary }
        return isPressed ? .primary : .secondary
    }
}
