import AppKit
import SwiftUI

/// パネルの開け閉め。
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let panel: PromptPanel
    private let settings: AppSettings
    private let targetTracker: FrontmostAppTracker
    private let permission: AccessibilityPermissionChecking
    private let performer: CommitPerformer
    private let fieldProbe: FocusedElementProbing
    private let ownProcessIdentifier: pid_t

    private let sizing = PanelSizing()
    private var liveResizeStartSize: CGSize?

    var heldPanelSize: CGSize? { sizing.heldSize }

    var onPermissionDenied: (() -> Void)? {
        get { performer.onPermissionDenied }
        set { performer.onPermissionDenied = newValue }
    }

    /// 返した挿入先を、前面のアプリの代わりに挿入先にする。`nil` を返すと前面のアプリを使う。
    var targetOverride: (() -> InsertionTarget?)?

    /// 確定で挿入することになったとき、パネルを閉じた後・挿入の前に呼ばれる。
    var onInsertionRequested: ((String, InsertionTarget) -> Void)?

    init(
        model: PanelModel = PanelModel(),
        settings: AppSettings,
        targetTracker: FrontmostAppTracker,
        inserter: TextInserting = ClipboardTextInserter(),
        permission: AccessibilityPermissionChecking = SystemAccessibilityPermission(),
        notifier: InsertionFailureNotifying = InsertionFailureNotifier(),
        fieldProbe: FocusedElementProbing = AXFocusedTextInputInspector(),
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.model = model
        self.panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.settings = settings
        self.targetTracker = targetTracker
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter, notifier: notifier)
        self.fieldProbe = fieldProbe
        self.ownProcessIdentifier = ownProcessIdentifier
        super.init()

        let hostingView = NSHostingView(
            rootView: PanelView(
                model: model,
                settings: settings,
                onKeyInput: { [weak self] in self?.handleKey($0) ?? false },
                onClose: { [weak self] in self?.closeFromButton() }
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        panel.delegate = self
    }

    /// 挿入先のアプリへアクセシビリティの問い合わせをしてよいか。自分自身が挿入先のときは問い合わせない。
    static func shouldQueryAccessibility(of target: InsertionTarget?, ownProcessIdentifier: pid_t) -> Bool {
        guard let target else { return false }
        return target.processIdentifier != ownProcessIdentifier
    }

    func open() {
        let target = targetOverride?() ?? targetTracker.currentTarget()
        let wasPresented = model.present(target: target)
        if !wasPresented {
            sizing.beginOpening(defaultSize: settings.panelDefaultSize)
            let queriesAccessibility = Self.shouldQueryAccessibility(
                of: target,
                ownProcessIdentifier: ownProcessIdentifier
            )
            if let target, queriesAccessibility, permission.isTrusted {
                AXFocusedTextInputInspector.exposeWebContent(of: target)
            }
            let mode = settings.panelScreen
            var targetWindowFrame: CGRect?
            if mode.usesTargetWindowFrame, let target {
                targetWindowFrame = TargetWindowLocator.frontWindowFrame(processIdentifier: target.processIdentifier)
            }
            let fieldFrame = NSScreen.screens.first.flatMap { primaryScreen in
                PanelOpenPlacement.fieldFrame(
                    mode: mode,
                    isTrusted: permission.isTrusted,
                    target: queriesAccessibility ? target : nil,
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

    func closeFromButton() {
        Self.commitMarkedText(in: panel)
        close()
    }

    static func commitMarkedText(in window: NSWindow) {
        (window.firstResponder as? PromptTextView)?.commitMarkedText()
    }

    func handleKey(_ input: PanelKeyInput) -> Bool {
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

    func commit(shouldSendAfterInsert: Bool = false) {
        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        panel.orderOut(nil)
        if case .insert(let text, let target) = plan {
            onInsertionRequested?(text, target)
        }
        Task { [weak self, performer] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            self?.sizing.handleCommitOutcome(outcome)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.dismiss()
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeStartSize = panel.frame.size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        defer { liveResizeStartSize = nil }
        guard let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: panel.frame.size)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, PanelSizing.minimumSize.width),
            height: max(frameSize.height, PanelSizing.minimumSize.height)
        )
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
