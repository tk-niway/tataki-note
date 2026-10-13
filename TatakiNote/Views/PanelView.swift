import AppKit
import SwiftUI

/// パネルの中身。
struct PanelView: View {
    @Bindable var model: PanelModel
    let settings: AppSettings
    let onKeyInput: (PanelKeyInput) -> Bool
    let onClose: () -> Void
    let onCommit: () -> Void
    let onCommitAndSend: () -> Void
    let session: DraftSession?
    let sidebarModel: SidebarModel?
    let saveAnimation: SaveAnimationModel?
    let onToggleSidebar: () -> Void
    let onNewDraft: () -> Void
    let onSaveDraft: () -> Void
    let onResolveConfirmation: ((UnsavedTextChoice) -> Void)?
    let onOpenSettings: () -> Void
    let appIcon: @MainActor (InsertionTarget) -> NSImage

    init(
        model: PanelModel,
        settings: AppSettings,
        onKeyInput: @escaping (PanelKeyInput) -> Bool,
        onClose: @escaping () -> Void,
        onCommit: @escaping () -> Void = {},
        onCommitAndSend: @escaping () -> Void = {},
        session: DraftSession? = nil,
        sidebarModel: SidebarModel? = nil,
        saveAnimation: SaveAnimationModel? = nil,
        onToggleSidebar: @escaping () -> Void = {},
        onNewDraft: @escaping () -> Void = {},
        onSaveDraft: @escaping () -> Void = {},
        onResolveConfirmation: ((UnsavedTextChoice) -> Void)? = nil,
        onOpenSettings: @escaping () -> Void = {},
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = { InsertionTargetBadge.systemIcon(for: $0) }
    ) {
        self.model = model
        self.settings = settings
        self.onKeyInput = onKeyInput
        self.onClose = onClose
        self.onCommit = onCommit
        self.onCommitAndSend = onCommitAndSend
        self.session = session
        self.sidebarModel = sidebarModel
        self.saveAnimation = saveAnimation
        self.onToggleSidebar = onToggleSidebar
        self.onNewDraft = onNewDraft
        self.onSaveDraft = onSaveDraft
        self.onResolveConfirmation = onResolveConfirmation
        self.onOpenSettings = onOpenSettings
        self.appIcon = appIcon
    }

    private static let placeholderInset = NSSize(
        width: PanelMetrics.textContainerInset.width + NSTextContainer().lineFragmentPadding,
        height: PanelMetrics.textContainerInset.height
    )

    /// 入力欄が空のときに出す薄い文字。
    static let placeholderText = String(localized: "ここにプロンプトを書く…")

    var body: some View {
        let isSidebarOpen = sidebarModel?.isOpen ?? false
        let slidingBodyWidth = sidebarModel?.slidingBodyWidth
        HStack(spacing: 0) {
            if let sidebarModel, isSidebarOpen {
                SidebarView(
                    model: sidebarModel,
                    glowingDraftID: saveAnimation?.glowingDraftID,
                    onOpenSettings: onOpenSettings
                )
                    .frame(
                        minWidth: 0,
                        maxWidth: slidingBodyWidth == nil ? SidebarLayout.width : .infinity,
                        alignment: .leading
                    )
                    .clipped()
                    .ignoresSafeArea(edges: .top)
                Divider()
                    .ignoresSafeArea(edges: .top)
            }
            bodyColumn
                .frame(width: slidingBodyWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowStyle(theme: settings.theme, opacity: settings.panelOpacity)
        .overlay(alignment: .top) {
            PanelTitleBar(
                target: model.target,
                showsInsertionTarget: !settings.isNoteMode,
                noTargetAlertCount: model.noTargetAlertCount,
                session: session,
                isSidebarOpen: isSidebarOpen,
                onClose: onClose,
                onToggleSidebar: onToggleSidebar,
                onNewDraft: onNewDraft,
                onSaveDraft: onSaveDraft,
                appIcon: appIcon
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlayPreferenceValue(SidebarToggleAnchorKey.self) { anchor in
            if let saveAnimation {
                SaveAnimationOverlay(model: saveAnimation, toggleAnchor: anchor)
            }
        }
    }

    private var bodyColumn: some View {
        let font = settings.panelFont
        let content = statusBarContent
        let isConfirming = session?.pendingSwitch != nil
        return VStack(spacing: 0) {
            Color.clear.frame(height: PanelMetrics.titleBarHeight)
            PromptTextEditor(
                text: $model.text,
                focusRequest: model.focusRequest,
                font: font,
                placeholder: Self.placeholderText,
                onKeyInput: onKeyInput
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text(verbatim: Self.placeholderText)
                            .font(Font(font as CTFont))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, Self.placeholderInset.width)
                            .padding(.top, Self.placeholderInset.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            if !content.isEmpty {
                Divider()
                PanelStatusBar(content: content, onCommit: onCommit, onCommitAndSend: onCommitAndSend)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityHidden(isConfirming)
        .overlay {
            if let session, session.pendingSwitch != nil {
                PanelConfirmationOverlay(focusedChoice: session.confirmationFocus) { choice in
                    if let onResolveConfirmation {
                        onResolveConfirmation(choice)
                    } else {
                        session.resolvePendingSwitch(choice)
                    }
                }
                .padding(.top, PanelMetrics.titleBarHeight)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var statusBarContent: PanelStatusBarContent {
        PanelStatusBarContent(
            text: model.text,
            items: settings.panelStatusItems,
            commitKeyText: settings.commitKeyDisplayText,
            commitAndSendKeyText: settings.commitAndSendKeyDisplayText
        )
    }
}
