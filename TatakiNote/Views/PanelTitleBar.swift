import AppKit
import SwiftUI

/// パネルの上部に重ねる、閉じる・開閉・新規作成・保存・挿入先のバー。
struct PanelTitleBar: View {
    let target: InsertionTarget?
    let session: DraftSession?
    let isSidebarOpen: Bool
    let onClose: () -> Void
    let onToggleSidebar: () -> Void
    let onNewDraft: () -> Void
    let onSaveDraft: () -> Void
    let appIcon: @MainActor (InsertionTarget) -> NSImage

    init(
        target: InsertionTarget?,
        session: DraftSession? = nil,
        isSidebarOpen: Bool = false,
        onClose: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void = {},
        onNewDraft: @escaping () -> Void = {},
        onSaveDraft: @escaping () -> Void = {},
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = InsertionTargetBadge.systemIcon(for:)
    ) {
        self.target = target
        self.session = session
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
            InsertionTargetView(target: target, appIcon: appIcon)
                .padding(.leading, 10)
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
        }
        .buttonStyle(TitleBarIconButtonStyle())
        .focusable(false)
        .help("下書きと履歴(⌘K で検索)")
        .accessibilityLabel("サイドバー")
        .accessibilityValue(isSidebarOpen ? "開いています" : "閉じています")
        .accessibilityIdentifier("promptPanel.sidebarToggle")
    }

    private var newDraftButton: some View {
        Button(action: onNewDraft) {
            iconLabel("square.and.pencil")
        }
        .buttonStyle(TitleBarIconButtonStyle())
        .focusable(false)
        .disabled(!(session?.isNewDraftAvailable ?? false) || session?.pendingSwitch != nil)
        .help("新しい書きかけ(⌘N)")
        .accessibilityLabel("新しい書きかけ")
        .accessibilityIdentifier("promptPanel.newDraftButton")
    }

    private var saveDraftButton: some View {
        Button(action: onSaveDraft) {
            iconLabel("square.and.arrow.down")
        }
        .buttonStyle(TitleBarIconButtonStyle())
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

    private struct TitleBarIconButtonStyle: ButtonStyle {
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
}
