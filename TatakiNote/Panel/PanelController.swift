import AppKit
import SwiftUI

/// パネルの開け閉め。
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    let panel: PromptPanel
    private let settings: AppSettings
    private let targetTracker: FrontmostAppTracker
    private let permission: AccessibilityPermissionChecking
    private let performer: CommitPerformer
    private let fieldProbe: FocusedElementProbing
    private let exposeWebContent: (InsertionTarget) -> Void
    private let locateTargetWindowFrame: (pid_t) -> CGRect?
    private let ownProcessIdentifier: pid_t
    private let library: DraftLibrary

    let session: DraftSession
    let sidebarModel: SidebarModel
    let saveAnimation: SaveAnimationModel

    private let sizing = PanelSizing()
    private var liveResizeStartSize: CGSize?
    var isAdjustingFrameForSidebar = false

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
        library: DraftLibrary = DraftLibrary(store: .inMemory),
        saveAnimation: SaveAnimationModel = SaveAnimationModel()
    ) {
        self.model = model
        self.panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.settings = settings
        self.targetTracker = targetTracker
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter, notifier: notifier)
        self.fieldProbe = fieldProbe
        self.exposeWebContent = exposeWebContent
        self.locateTargetWindowFrame = locateTargetWindowFrame
        self.ownProcessIdentifier = ownProcessIdentifier
        self.library = library
        let session = DraftSession(panel: model, library: library, ownProcessIdentifier: ownProcessIdentifier)
        self.session = session
        self.sidebarModel = SidebarModel(settings: settings, library: library, session: session)
        self.saveAnimation = saveAnimation
        super.init()

        let hostingView = NSHostingView(
            rootView: PanelView(
                model: model,
                settings: settings,
                onKeyInput: { [weak self] in self?.handleKey($0) ?? false },
                onClose: { [weak self] in self?.closeFromButton() },
                session: session,
                sidebarModel: sidebarModel,
                saveAnimation: saveAnimation,
                onToggleSidebar: { [weak self] in self?.toggleSidebarFromButton() },
                onNewDraft: { [weak self] in self?.newDraftFromButton() },
                onSaveDraft: { [weak self] in self?.saveDraftFromButton() },
                onResolveConfirmation: { [weak self] in self?.resolveConfirmationFromButton($0) }
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.handleKey($0) ?? false }
        applyMinimumSize()
        configureSidebarModel()
        observeBodyFocusRequests()
        observeSaveEvents()
    }

    private func observeSaveEvents() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.session.lastSaveEvent },
            onChange: { [weak self] in
                guard let self else { return false }
                if let event = self.session.lastSaveEvent {
                    let animation = self.saveAnimation
                    let isSidebarOpen = self.sidebarModel.isOpen
                    Task { await animation.play(event, isSidebarOpen: isSidebarOpen) }
                }
                return true
            }
        )
    }

    private func configureSidebarModel() {
        let panel = panel
        sidebarModel.markedTextProbe = { [weak panel] in
            PromptPanel.firstResponderHasMarkedText(panel?.firstResponder)
        }
        sidebarModel.beforeUserAction = { [weak panel] in
            if let panel {
                Self.commitMarkedText(in: panel)
            }
        }
    }

    private func observeBodyFocusRequests() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.sidebarModel.bodyFocusRequest },
            onChange: { [weak self] in
                guard let self else { return false }
                self.model.requestFocus()
                return true
            }
        )
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
                let frame = sidebarModel.isOpen
                    ? SidebarLayout.expandedFrame(bodyFrame: placed, visibleFrame: screen.visibleFrame)
                    : placed
                applyMinimumSize()
                panel.setFrame(frame, display: false)
            } else {
                applyMinimumSize()
                panel.center()
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        session.resolvePendingSwitch(.cancel)
        sidebarModel.cancelDeletion()
        panel.orderOut(nil)
        model.dismiss()
        library.flush()
    }

    /// 遅らせている下書きの書き出しを今行う。
    func flushDrafts() {
        library.flush()
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
        if session.pendingSwitch != nil {
            return handleConfirmationKey(input)
        }
        if sidebarModel.pendingDeletion != nil {
            return handleDeletionConfirmationKey(input)
        }
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
        case .openSearch:
            if !sidebarModel.isOpen {
                setSidebarOpen(true)
            }
            sidebarModel.openForSearch()
            return true
        case .saveDraft:
            session.saveCurrent()
            return true
        case .newDraft:
            requestNewScratch()
            return true
        case .passThrough:
            return false
        }
    }

    private func handleConfirmationKey(_ input: PanelKeyInput) -> Bool {
        guard !input.hasMarkedText else { return false }
        if let choice = PanelKeyResolver.confirmationChoice(for: input) {
            session.resolvePendingSwitch(choice)
        }
        return true
    }

    private func handleDeletionConfirmationKey(_ input: PanelKeyInput) -> Bool {
        guard !input.hasMarkedText else { return false }
        switch PanelKeyResolver.deletionConfirmationKey(for: input) {
        case .delete:
            sidebarModel.confirmDeletion()
        case .cancel:
            sidebarModel.cancelDeletion()
        case nil:
            break
        }
        return true
    }

    // MARK: - クリックの操作

    /// タイトルバーの新規作成のアイコン。変換中の文字を確定してから新しい書きかけにする。
    func newDraftFromButton() {
        guard session.pendingSwitch == nil else { return }
        Self.commitMarkedText(in: panel)
        requestNewScratch()
    }

    private func requestNewScratch() {
        session.request(.newScratch)
        if session.pendingSwitch != nil {
            model.requestFocus()
        }
    }

    /// タイトルバーの保存のアイコン。変換中の文字を確定してから下書きに保存する。
    func saveDraftFromButton() {
        guard session.pendingSwitch == nil else { return }
        Self.commitMarkedText(in: panel)
        session.saveCurrent()
        model.requestFocus()
    }

    /// 確認の重ね表示のボタン。変換中の文字を確定してから答えを反映する。
    func resolveConfirmationFromButton(_ choice: UnsavedTextChoice) {
        Self.commitMarkedText(in: panel)
        session.resolvePendingSwitch(choice)
    }

    /// タイトルバーのサイドバーの開閉ボタン。
    func toggleSidebarFromButton() {
        setSidebarOpen(!sidebarModel.isOpen)
        model.requestFocus()
    }

    // MARK: - サイドバー

    /// サイドバーを開閉する。パネルが開いていれば、窓の枠をサイドバーの幅だけ変える。
    func setSidebarOpen(_ isOpen: Bool) {
        let wasOpen = sidebarModel.isOpen
        guard isOpen != wasOpen else { return }
        guard model.isPresented else {
            sidebarModel.setOpen(isOpen)
            applyMinimumSize()
            return
        }
        isAdjustingFrameForSidebar = true
        defer { isAdjustingFrameForSidebar = false }
        if isOpen {
            let frame = SidebarLayout.expandedFrame(bodyFrame: panel.frame, visibleFrame: visibleFrameForSidebar)
            panel.setFrame(frame, display: true, animate: false)
            sidebarModel.setOpen(true)
            applyMinimumSize()
        } else {
            sidebarModel.setOpen(false)
            applyMinimumSize()
            panel.setFrame(SidebarLayout.collapsedFrame(expandedFrame: panel.frame), display: true, animate: false)
        }
    }

    private var visibleFrameForSidebar: CGRect {
        panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame.insetBy(dx: -SidebarLayout.width, dy: 0)
    }

    private func applyMinimumSize() {
        panel.contentMinSize = SidebarLayout.minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
    }

    // MARK: - 確定

    func commit(shouldSendAfterInsert: Bool = false) {
        let plan = session.prepareCommit {
            model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        }
        panel.orderOut(nil)
        library.flush()
        if case .insert(let text, let target) = plan {
            onInsertionRequested?(text, target, shouldSendAfterInsert)
        }
        Task { [weak self, performer] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            self?.sizing.handleCommitOutcome(outcome)
            self?.session.finishCommit(plan, outcome: outcome)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.dismiss()
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(_ notification: Notification) {
        guard !isAdjustingFrameForSidebar else { return }
        liveResizeStartSize = bodySize(of: panel.frame.size)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        defer { liveResizeStartSize = nil }
        guard !isAdjustingFrameForSidebar, let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = SidebarLayout.minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    private func bodySize(of windowSize: CGSize) -> CGSize {
        SidebarLayout.bodySize(windowSize: windowSize, isSidebarOpen: sidebarModel.isOpen)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
