import AppKit
import SwiftUI

/// @note p0-468
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let panel: PromptPanel
    private let settings: AppSettings
    private let targetTracker: FrontmostAppTracker
    private let permission: AccessibilityPermissionChecking
    private let performer: CommitPerformer
    private let fieldProbe: FocusedElementProbing

    /// @note p0-469
    private let sizing = PanelSizing()
    /// @note p0-470
    private var liveResizeStartSize: CGSize?

    /// @note p0-471
    var heldPanelSize: CGSize? { sizing.heldSize }

    /// @note p0-472
    var onPermissionDenied: (() -> Void)? {
        get { performer.onPermissionDenied }
        set { performer.onPermissionDenied = newValue }
    }

    /// @note p0-473
    init(
        model: PanelModel = PanelModel(),
        settings: AppSettings,
        targetTracker: FrontmostAppTracker,
        inserter: TextInserting = ClipboardTextInserter(),
        permission: AccessibilityPermissionChecking = SystemAccessibilityPermission(),
        notifier: InsertionFailureNotifying = InsertionFailureNotifier(),
        fieldProbe: FocusedElementProbing = AXFocusedTextInputInspector()
    ) {
        self.model = model
        // @note p0-474
        self.panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.settings = settings
        self.targetTracker = targetTracker
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter, notifier: notifier)
        self.fieldProbe = fieldProbe
        super.init()

        let hostingView = NSHostingView(
            rootView: PanelView(
                model: model,
                settings: settings,
                onKeyInput: { [weak self] in self?.handleKey($0) ?? false },
                onClose: { [weak self] in self?.closeFromButton() }
            )
        )
        // @note p0-475
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        panel.delegate = self
    }

    func open() {
        let target = targetTracker.currentTarget()
        let wasPresented = model.present(target: target)
        // @note p0-476
        if !wasPresented {
            // @note p0-477
            sizing.beginOpening(defaultSize: settings.panelDefaultSize)
            // @note p0-478
            if let target, permission.isTrusted {
                AXFocusedTextInputInspector.exposeWebContent(of: target)
            }
            let mode = settings.panelScreen
            var targetWindowFrame: CGRect?
            if mode.usesTargetWindowFrame, let target {
                targetWindowFrame = TargetWindowLocator.frontWindowFrame(processIdentifier: target.processIdentifier)
            }
            // @note p0-479
            let fieldFrame = NSScreen.screens.first.flatMap { primaryScreen in
                PanelOpenPlacement.fieldFrame(
                    mode: mode,
                    isTrusted: permission.isTrusted,
                    target: target,
                    probe: fieldProbe,
                    primaryScreenHeight: primaryScreen.frame.height
                )
            }
            let screens = NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
            if let screen = PanelOpenPlacement.screen(
                mode: mode,
                screens: screens,
                mouseLocation: NSEvent.mouseLocation,
                targetWindowFrame: targetWindowFrame,
                fieldFrame: fieldFrame
            ) {
                let placed = PanelOpenPlacement.frame(
                    size: sizing.openingSize(in: screen.visibleFrame),
                    on: screen,
                    mode: mode,
                    fieldFrame: fieldFrame
                )
                panel.setFrame(placed, display: false)
            } else {
                panel.center()
            }
        }
        // @note p0-480
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
        model.dismiss()
    }

    func toggle() {
        if model.isPresented {
            close()
        } else {
            open()
        }
    }

    /// @note p0-481
    func closeFromButton() {
        Self.commitMarkedText(in: panel)
        close()
    }

    /// @note p0-482
    static func commitMarkedText(in window: NSWindow) {
        (window.firstResponder as? PromptTextView)?.commitMarkedText()
    }

    /// @note p0-483
    func handleKey(_ input: PanelKeyInput) -> Bool {
        // @note p0-484
        switch PanelKeyResolver.action(
            for: input,
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey
        ) {
        case .cancel:
            close()
            return true
        case .commit:
            commit(shouldSendAfterInsert: false)
            return true
        case .commitAndSend:
            commit(shouldSendAfterInsert: true)
            return true
        case .passThrough:
            return false
        }
    }

    /// @note p0-485
    func commit(shouldSendAfterInsert: Bool = false) {
        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        // @note p0-486
        panel.orderOut(nil)
        Task { [weak self, performer] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            // @note p0-487
            self?.sizing.handleCommitOutcome(outcome)
        }
    }

    // @note p0-488
    func windowWillClose(_ notification: Notification) {
        model.dismiss()
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeStartSize = panel.frame.size
    }

    /// @note p0-489
    func windowDidEndLiveResize(_ notification: Notification) {
        defer { liveResizeStartSize = nil }
        // @note p0-490
        guard let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: panel.frame.size)
    }

    /// @note p0-491
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, PanelSizing.minimumSize.width),
            height: max(frameSize.height, PanelSizing.minimumSize.height)
        )
    }

    /// @note p0-492
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
