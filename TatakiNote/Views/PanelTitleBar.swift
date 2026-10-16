import AppKit
import SwiftUI

/// パネルの上部に重ねる、閉じる・開閉・新規作成・保存・挿入先のバー。
struct PanelTitleBar: View {
    let target: InsertionTarget?
    let noTargetAlertCount: Int
    let session: DraftSession?
    let isSidebarOpen: Bool
    let saveArrival: SaveArrival
    let onClose: () -> Void
    let onToggleSidebar: () -> Void
    let onNewDraft: () -> Void
    let onSaveDraft: () -> Void
    let appIcon: @MainActor (InsertionTarget) -> NSImage
    let showsInsertionTarget: Bool

    init(
        target: InsertionTarget?,
        showsInsertionTarget: Bool = true,
        noTargetAlertCount: Int = 0,
        session: DraftSession? = nil,
        isSidebarOpen: Bool = false,
        saveArrival: SaveArrival = SaveArrival(),
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
        self.isSidebarOpen = isSidebarOpen
        self.saveArrival = saveArrival
        self.onClose = onClose
        self.onToggleSidebar = onToggleSidebar
        self.onNewDraft = onNewDraft
        self.onSaveDraft = onSaveDraft
        self.appIcon = appIcon
    }

    private static let closeHitSize: CGFloat = 20
    private static let closeDiameter: CGFloat = 16
    private static let buttonSize = CGSize(width: 26, height: 22)
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
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: Self.closeDiameter, height: Self.closeDiameter)
                .frame(width: Self.closeHitSize, height: Self.closeHitSize)
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
                .saveFlightAnchor(.sidebarToggle)
                .saveArrivalBounce(for: .sidebarToggle, arrival: saveArrival)
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
        .disabled(!(session?.isNewDraftAvailable ?? false))
        .help("新しい書きかけ(⌘N)")
        .accessibilityLabel("新しい書きかけ")
        .accessibilityIdentifier("promptPanel.newDraftButton")
    }

    private var saveDraftButton: some View {
        Button(action: onSaveDraft) {
            iconLabel("square.and.arrow.down")
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .help("下書きに保存(⌘S)")
        .accessibilityLabel("下書きに保存")
        .accessibilityIdentifier("promptPanel.saveDraftButton")
    }

    private func iconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Self.iconSize))
            .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
            .contentShape(Rectangle())
    }

    // MARK: - スタイル

    private struct CloseButtonStyle: ButtonStyle {
        @State private var isHovering = false

        private static let hoverFill = Color(red: 1, green: 0.373, blue: 0.341)
        private static let hoverMark = Color(red: 0.302, green: 0, blue: 0)

        func makeBody(configuration: Configuration) -> some View {
            let isActive = isHovering || configuration.isPressed
            return configuration.label
                .foregroundStyle(isActive ? Self.hoverMark : Color.secondary)
                .background {
                    Circle()
                        .fill(isActive ? Self.hoverFill : Color.primary.opacity(0.18))
                        .frame(width: PanelTitleBar.closeDiameter, height: PanelTitleBar.closeDiameter)
                }
                .onHover { isHovering = $0 }
        }
    }
}

/// パネルのアイコンのボタンの見た目。ホバーで薄い背景を敷き、押している間は濃くする。
struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(backgroundOpacity(isPressed: configuration.isPressed)))
            }
            .onHover { isHovering = $0 }
    }

    private func foreground(isPressed: Bool) -> HierarchicalShapeStyle {
        if !isEnabled { return .tertiary }
        return isPressed ? .primary : .secondary
    }

    private func backgroundOpacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0 }
        if isPressed { return 0.24 }
        return isHovering ? 0.14 : 0
    }
}
