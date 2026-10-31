import AppKit
import SwiftUI

/// パネルの中身。
struct PanelView: View {
    @Bindable var model: PanelModel
    let settings: AppSettings
    let onKeyInput: (PanelKeyInput) -> Bool
    let onCommand: (PanelCommand) -> Void
    let session: DraftSession?
    let sidebarModel: SidebarModel?
    let saveAnimation: SaveAnimationModel?
    let sharingAnchorRegistry: SharingAnchorRegistry?
    let appIcon: @MainActor (InsertionTarget) -> NSImage

    init(
        model: PanelModel,
        settings: AppSettings,
        onKeyInput: @escaping (PanelKeyInput) -> Bool,
        onCommand: @escaping (PanelCommand) -> Void = { _ in },
        session: DraftSession? = nil,
        sidebarModel: SidebarModel? = nil,
        saveAnimation: SaveAnimationModel? = nil,
        sharingAnchorRegistry: SharingAnchorRegistry? = nil,
        appIcon: @escaping @MainActor (InsertionTarget) -> NSImage = { InsertionTargetBadge.systemIcon(for: $0) }
    ) {
        self.model = model
        self.settings = settings
        self.onKeyInput = onKeyInput
        self.onCommand = onCommand
        self.session = session
        self.sidebarModel = sidebarModel
        self.saveAnimation = saveAnimation
        self.sharingAnchorRegistry = sharingAnchorRegistry
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
        let arrival = saveArrival
        HStack(spacing: 0) {
            if let sidebarModel, isSidebarOpen {
                SidebarView(
                    model: sidebarModel,
                    glowingDraftID: saveAnimation?.glowingDraftID,
                    glowCount: saveAnimation?.glowCount ?? 0,
                    saveArrival: arrival,
                    onOpenSettings: { onCommand(.openSettings) }
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
                mode: session?.mode ?? .insert,
                noTargetAlertCount: model.noTargetAlertCount,
                isTargetPending: model.isTargetPending,
                session: session,
                isSidebarOpen: isSidebarOpen,
                saveArrival: arrival,
                onCommand: onCommand,
                sharingAnchorRegistry: sharingAnchorRegistry,
                appIcon: appIcon
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlayPreferenceValue(SaveFlightAnchorKey.self) { anchors in
            if let saveAnimation {
                SaveAnimationOverlay(
                    model: saveAnimation,
                    anchors: anchors,
                    bodyLeadingInset: bodyLeadingInset(isSidebarOpen: isSidebarOpen, slidingBodyWidth: slidingBodyWidth)
                )
            }
        }
        .appAnimation(mode: settings.animationMode)
    }

    private var saveArrival: SaveArrival {
        guard let saveAnimation else { return SaveArrival() }
        var destination: SaveFlightDestination?
        if case .arrived(let flight) = saveAnimation.phase {
            destination = flight.destination
        }
        return SaveArrival(count: saveAnimation.arrivalCount, destination: destination)
    }

    private func bodyLeadingInset(isSidebarOpen: Bool, slidingBodyWidth: CGFloat?) -> CGFloat {
        guard isSidebarOpen, slidingBodyWidth == nil else { return 0 }
        return SidebarLayout.width + 1
    }

    private var saveToastBottomInset: CGFloat {
        let bandHeight = statusBarContent.isEmpty ? 0 : PanelMetrics.statusBarHeight + 1
        return bandHeight + 12
    }

    private var bodyColumn: some View {
        let font = settings.panelFont
        let content = statusBarContent
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
                PanelStatusBar(content: content, onCommand: onCommand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            if let saveAnimation, let message = saveAnimation.toastMessage {
                PanelToastView(message: message, style: saveAnimation.toastStyle)
                    .id(saveAnimation.toastCount)
                    .padding(.bottom, saveToastBottomInset)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("promptPanel.saveToast")
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var statusBarContent: PanelStatusBarContent {
        PanelStatusBarContent(
            text: model.text,
            items: settings.panelStatusItems(for: session?.mode ?? .insert),
            commitKeyText: settings.commitKeyDisplayText,
            commitAndSendKeyText: settings.commitAndSendKeyDisplayText
        )
    }
}
