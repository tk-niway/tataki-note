import AppKit
import SwiftUI

/// パネルの開け閉め。
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    /// 入力パネルの窓。
    let panel: PromptPanel
    private let settings: AppSettings
    private let animator: PanelFrameAnimating
    private let hideApplication: () -> Void
    private let targetTracker: FrontmostAppTracker
    private let permission: AccessibilityPermissionChecking
    private let performer: CommitPerformer
    private let fieldProbe: FocusedElementProbing
    private let exposeWebContent: (InsertionTarget) -> Void
    private let locateTargetWindowFrame: (pid_t) -> CGRect?
    private let ownProcessIdentifier: pid_t

    private let sizing = PanelSizing()
    private var liveResizeStartSize: CGSize?

    private var motion = PanelMotionState()
    private var restingFrame: NSRect?
    private var pendingCloseCompletion: (() -> Void)?

    var heldPanelSize: CGSize? { sizing.heldSize }

    var onPermissionDenied: (() -> Void)? {
        get { performer.onPermissionDenied }
        set { performer.onPermissionDenied = newValue }
    }

    /// 返した挿入先を、前面のアプリの代わりに挿入先にする。`nil` を返すと前面のアプリを使う。
    var targetOverride: (() -> InsertionTarget?)?

    /// 確定で挿入することになったとき、パネルを閉じた後・挿入の前に、文章・挿入先・送信もするかを知らせる。
    var onInsertionRequested: ((String, InsertionTarget, Bool) -> Void)?

    init(
        model: PanelModel = PanelModel(),
        settings: AppSettings,
        targetTracker: FrontmostAppTracker,
        inserter: TextInserting = ClipboardTextInserter(),
        permission: AccessibilityPermissionChecking = SystemAccessibilityPermission(),
        notifier: InsertionFailureNotifying = InsertionFailureNotifier(),
        fieldProbe: FocusedElementProbing = AXFocusedTextInputInspector(),
        exposeWebContent: @escaping (InsertionTarget) -> Void = { AXFocusedTextInputInspector.exposeWebContent(of: $0) },
        locateTargetWindowFrame: @escaping (pid_t) -> CGRect? = { TargetWindowLocator.frontWindowFrame(processIdentifier: $0) },
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        animator: PanelFrameAnimating = AppKitPanelFrameAnimator(),
        hideApplication: @escaping () -> Void = { NSApp.hide(nil) }
    ) {
        self.model = model
        self.panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.settings = settings
        self.animator = animator
        self.hideApplication = hideApplication
        self.targetTracker = targetTracker
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter, notifier: notifier)
        self.fieldProbe = fieldProbe
        self.exposeWebContent = exposeWebContent
        self.locateTargetWindowFrame = locateTargetWindowFrame
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
        panel.onHideKey = { [weak self] in self?.handleHideKey() ?? false }
    }

    /// 挿入先のアプリへアクセシビリティの問い合わせをしてよいか。自分自身が挿入先のときは問い合わせない。
    static func shouldQueryAccessibility(of target: InsertionTarget?, ownProcessIdentifier: pid_t) -> Bool {
        guard let target else { return false }
        return !target.isOwnApp(ownProcessIdentifier)
    }

    /// パネルを開くときに、挿入先へ Web の中身を出すよう頼むか。
    static func shouldExposeWebContent(target: InsertionTarget?, ownProcessIdentifier: pid_t, isTrusted: Bool) -> Bool {
        shouldQueryAccessibility(of: target, ownProcessIdentifier: ownProcessIdentifier) && isTrusted
    }

    /// 挿入先のウィンドウの枠を求めるクロージャ。挿入先が無ければ一覧を取らずに `nil` を返す。
    static func windowFrameLocator(
        for target: InsertionTarget?,
        locate: @escaping (pid_t) -> CGRect?
    ) -> () -> CGRect? {
        { target.flatMap { locate($0.processIdentifier) } }
    }

    func open(observedFocus: ObservedFocus? = nil) {
        let target = targetOverride?() ?? targetTracker.currentTarget()
        settings.refreshKeyDisplayTexts()
        let wasPresented = model.present(target: target)
        if !wasPresented {
            stopMotion()
            sizing.beginOpening(defaultSize: settings.panelDefaultSize)
            let queriesAccessibility = Self.shouldQueryAccessibility(
                of: target,
                ownProcessIdentifier: ownProcessIdentifier
            )
            let isTrusted = permission.isTrusted
            if let target,
               Self.shouldExposeWebContent(
                   target: target,
                   ownProcessIdentifier: ownProcessIdentifier,
                   isTrusted: isTrusted
               ) {
                exposeWebContent(target)
            }
            let mode = settings.panelScreen
            let fieldFrame = ScreenCoordinates.primaryScreenFrame.flatMap { primaryScreenFrame in
                PanelOpenPlacement.fieldFrame(
                    mode: mode,
                    isTrusted: isTrusted,
                    target: queriesAccessibility ? target : nil,
                    probe: fieldProbe,
                    observedFocus: observedFocus,
                    primaryScreenHeight: primaryScreenFrame.height
                )
            }
            let screens = NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
            if let screen = PanelOpenPlacement.screen(
                mode: mode,
                screens: screens,
                mouseLocation: NSEvent.mouseLocation,
                fieldFrame: fieldFrame,
                locateTargetWindowFrame: Self.windowFrameLocator(for: target, locate: locateTargetWindowFrame)
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
            present(at: panel.frame)
            return
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        hidePanel()
        model.dismiss()
    }

    /// アプリが隠れたときに、動きなしでパネルを閉じて枠を本来の枠に戻す。
    func closeImmediately() {
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        panel.orderOut(nil)
        if let frame = restingFrame {
            restingFrame = nil
            animator.jump(panel, to: frame)
        }
        endMotion()
        model.dismiss()
    }

    /// ⌘H を受け取る。アニメーションがオンで開いているときは閉じる動きのあとにアプリを隠して true を返す。
    func handleHideKey() -> Bool {
        guard settings.isPanelAnimationEnabled,
              motion.phase == .opening || motion.phase == .shown else { return false }
        hidePanel(then: { [weak self] in self?.hideApplication() })
        model.dismiss()
        return true
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
        hidePanel()
        if case .insert(let text, let target) = plan {
            onInsertionRequested?(text, target, shouldSendAfterInsert)
        }
        Task { [weak self, performer] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            self?.sizing.handleCommitOutcome(outcome)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.dismiss()
    }

    // MARK: - 開閉の動き

    private func present(at restFrame: NSRect) {
        guard settings.isPanelAnimationEnabled else {
            endMotion()
            panel.makeKeyAndOrderFront(nil)
            motion.showWithoutMotion()
            pendingCloseCompletion = nil
            restingFrame = nil
            return
        }
        beginMotion()
        restingFrame = restFrame
        panel.setFrame(PanelMotion.lineFrame(of: restFrame), display: false)
        panel.acceptsKey = true
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        let token = motion.beginOpening()
        pendingCloseCompletion = nil
        animator.animate(panel, to: restFrame, duration: PanelMotion.duration, curve: .easeOut) { [weak self] in
            self?.finishMotion(token)
        }
    }

    private func hidePanel(then completion: (() -> Void)? = nil) {
        guard settings.isPanelAnimationEnabled, motion.phase != .hidden else {
            panel.orderOut(nil)
            motion.hideWithoutMotion()
            pendingCloseCompletion = nil
            endMotion()
            if let frame = restingFrame {
                restingFrame = nil
                animator.jump(panel, to: frame)
            }
            completion?()
            return
        }
        if motion.phase == .closing { return }
        let originalFrame = motion.phase == .opening ? (restingFrame ?? panel.frame) : panel.frame
        restingFrame = originalFrame
        beginMotion()
        panel.acceptsKey = false
        panel.ignoresMouseEvents = true
        let token = motion.beginClosing()
        pendingCloseCompletion = completion
        let closingPanel = panel
        closingPanel.disableScreenUpdatesUntilFlush()
        closingPanel.orderOut(nil)
        closingPanel.orderFrontRegardless()
        animator.animate(
            closingPanel,
            to: PanelMotion.lineFrame(of: originalFrame),
            duration: PanelMotion.duration,
            curve: .easeIn
        ) { [weak self] in
            if let self {
                self.finishMotion(token)
            } else {
                closingPanel.orderOut(nil)
            }
        }
    }

    private func finishMotion(_ token: Int) {
        guard motion.finish(token) else { return }
        switch motion.phase {
        case .shown:
            restingFrame = nil
            endMotion()
        case .hidden:
            panel.orderOut(nil)
            if let frame = restingFrame {
                panel.setFrame(frame, display: false)
            }
            restingFrame = nil
            endMotion()
            let completion = pendingCloseCompletion
            pendingCloseCompletion = nil
            completion?()
        case .opening, .closing:
            break
        }
    }

    private func beginMotion() {
        panel.contentMinSize = NSSize(width: 1, height: 1)
    }

    private func endMotion() {
        panel.contentMinSize = PanelSizing.minimumSize
        panel.acceptsKey = true
        panel.ignoresMouseEvents = false
    }

    private func stopMotion() {
        guard motion.phase == .opening || motion.phase == .closing else { return }
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        let frame = restingFrame ?? panel.frame
        restingFrame = nil
        animator.jump(panel, to: frame)
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
        if motion.phase == .opening || motion.phase == .closing {
            return frameSize
        }
        return NSSize(
            width: max(frameSize.width, PanelSizing.minimumSize.width),
            height: max(frameSize.height, PanelSizing.minimumSize.height)
        )
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
