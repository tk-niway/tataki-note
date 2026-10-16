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
    private let library: DraftLibrary
    private let targetMonitor: InsertionTargetMonitor
    private let outlineController: InsertionTargetOutlineController
    private let shaker: PanelShaking

    let session: DraftSession
    let sidebarModel: SidebarModel
    let saveAnimation: SaveAnimationModel

    private let sizing = PanelSizing()
    private var liveResizeStartSize: CGSize?
    private var resizeStartSize: CGSize?
    var isAdjustingFrameForSidebar = false

    private var motion = PanelMotionState()
    private var restingFrame: NSRect?
    private var pendingCloseCompletion: (() -> Void)?
    private var closingGhost: PanelClosingGhost?
    private var sidebarSlide: SidebarSlide?
    private var sidebarSlideGeneration = 0

    private struct SidebarSlide {
        let generation: Int
        let frame: NSRect
        let isOpen: Bool
    }

    var heldPanelSize: CGSize? { sizing.heldSize }

    var onPermissionDenied: (() -> Void)? {
        get { performer.onPermissionDenied }
        set { performer.onPermissionDenied = newValue }
    }

    /// 返した挿入先を、前面のアプリの代わりに挿入先にする。`nil` を返すと前面のアプリを使う。
    var targetOverride: (() -> InsertionTarget?)?

    /// 挿入先を探さず、挿入先が無いものとして開くか。
    var isTargetLookupDisabled = false

    /// TatakiNote 自身が挿入先のとき、その入力欄がまだ使えるか。nil なら使えるとみなす。
    var isOwnTargetAvailable: (() -> Bool)? {
        get { targetMonitor.isOwnTargetAvailable }
        set { targetMonitor.isOwnTargetAvailable = newValue }
    }

    /// サイドバーの歯車のボタンと ⌘, で、パネルを閉じた後に呼ぶ処理。
    var onOpenSettings: (() -> Void)?

    /// 確定で挿入することになったとき、パネルを閉じた後・挿入の前に、文章・挿入先・送信もするかを知らせる。
    var onInsertionRequested: ((String, InsertionTarget, Bool) -> Void)?

    init(
        model: PanelModel = PanelModel(),
        settings: AppSettings,
        targetTracker: FrontmostAppTracker,
        inserter: TextInserting = ClipboardTextInserter(),
        permission: AccessibilityPermissionChecking = SystemAccessibilityPermission(),
        fieldProbe: FocusedElementProbing = AXFocusedTextInputInspector(),
        exposeWebContent: @escaping (InsertionTarget) -> Void = { AXFocusedTextInputInspector.exposeWebContent(of: $0) },
        locateTargetWindowFrame: @escaping (pid_t) -> CGRect? = { TargetWindowLocator.frontWindowFrame(processIdentifier: $0) },
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        library: DraftLibrary = DraftLibrary(store: .inMemory),
        saveAnimation: SaveAnimationModel = SaveAnimationModel(),
        animator: PanelFrameAnimating = AppKitPanelFrameAnimator(),
        shaker: PanelShaking = PanelShaker(),
        hideApplication: @escaping () -> Void = { NSApp.hide(nil) },
        makeTargetMonitor: ((PanelModel) -> InsertionTargetMonitor)? = nil
    ) {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.model = model
        self.panel = panel
        self.settings = settings
        self.animator = animator
        self.shaker = shaker
        self.hideApplication = hideApplication
        self.targetTracker = targetTracker
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter)
        self.fieldProbe = fieldProbe
        self.exposeWebContent = exposeWebContent
        self.locateTargetWindowFrame = locateTargetWindowFrame
        self.ownProcessIdentifier = ownProcessIdentifier
        self.library = library
        let targetMonitor = makeTargetMonitor?(model) ?? InsertionTargetMonitor(
            panelModel: model,
            probe: fieldProbe,
            ownProcessIdentifier: ownProcessIdentifier,
            exposeWebContent: exposeWebContent,
            isOutlineEnabled: { [settings] in settings.isInsertionTargetOutlineActive }
        )
        self.targetMonitor = targetMonitor
        self.outlineController = InsertionTargetOutlineController(
            outline: targetMonitor.outline,
            settings: settings,
            panelModel: model,
            panel: panel
        )
        let session = DraftSession(
            panel: model,
            library: library,
            ownProcessIdentifier: ownProcessIdentifier
        )
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
                onCommit: { [weak self] in self?.commitFromButton(shouldSendAfterInsert: false) },
                onCommitAndSend: { [weak self] in self?.commitFromButton(shouldSendAfterInsert: true) },
                session: session,
                sidebarModel: sidebarModel,
                saveAnimation: saveAnimation,
                onToggleSidebar: { [weak self] in self?.toggleSidebarFromButton() },
                onNewDraft: { [weak self] in self?.newDraftFromButton() },
                onSaveDraft: { [weak self] in self?.saveDraftFromButton() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.handleKey($0) ?? false }
        panel.onHideKey = { [weak self] in self?.handleHideKey() ?? false }
        panel.onKeyDownOutsideEditor = { [weak self] in self?.handleKeyOutsideEditor($0) ?? false }
        applyMinimumSize()
        configureSidebarModel()
        observeBodyFocusRequests()
        observeSaveEvents()
        observeAppMode()
        targetMonitor.onFieldAdopted = { [weak self] in self?.returnInputToPanel() }
    }

    private func observeAppMode() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.settings.appMode },
            onChange: { [weak self] in
                guard let self else { return false }
                self.applyAppMode()
                return true
            }
        )
    }

    /// 開いているパネルを今のモードに合わせる。ノートモードなら見張りをやめて挿入先なしにし、インサートモードなら挿入先なしから見張りを始める。
    func applyAppMode() {
        guard model.isPresented else { return }
        if settings.isNoteMode {
            targetMonitor.end()
            model.updateTarget(nil)
        } else {
            targetMonitor.begin(app: nil)
        }
    }

    private func observeSaveEvents() {
        observeRepeatedly(
            tracking: { [weak self] in _ = self?.session.lastSaveEvent },
            onChange: { [weak self] in
                guard let self else { return false }
                if let event = self.session.lastSaveEvent {
                    self.playSaveAnimation(for: event)
                }
                return true
            }
        )
    }

    private func playSaveAnimation(for event: DraftSaveEvent) {
        guard model.isPresented else { return }
        let id: UUID
        switch event.kind {
        case .created(let savedID), .overwritten(let savedID):
            id = savedID
        }
        if SaveFlightDestination.shouldSwitchToDrafts(
            isSidebarOpen: sidebarModel.isOpen,
            tab: sidebarModel.tab
        ) {
            sidebarModel.tab = .drafts
        }
        let text = library.draft(id: id)?.text ?? model.text
        let destination = SaveFlightDestination.resolve(
            savedDraftID: id,
            isSidebarOpen: sidebarModel.isOpen,
            isShowingDrafts: sidebarModel.tab == .drafts,
            visibleDraftIDs: sidebarModel.rows.map(\.id)
        )
        let animation = saveAnimation
        Task { await animation.play(text: text, destination: destination) }
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
        sidebarModel.closePanel = { [weak self] in self?.close() }
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
        let isNoteMode = settings.isNoteMode
        let app = isTargetLookupDisabled ? nil : (targetOverride?() ?? targetTracker.currentTarget())
        settings.refreshKeyDisplayTexts()
        let wasPresented = model.isPresented
        var start: InsertionTargetStart?
        let isTrusted = permission.isTrusted
        if !wasPresented, !isNoteMode {
            if let app,
               Self.shouldExposeWebContent(
                   target: app,
                   ownProcessIdentifier: ownProcessIdentifier,
                   isTrusted: isTrusted
               ) {
                exposeWebContent(app)
            }
            start = targetMonitor.begin(app: app, observedFocus: observedFocus)
        }
        model.present(target: wasPresented ? app : start?.target)
        if !wasPresented {
            sidebarModel.discardPendingFocusRequests()
            stopMotion()
            sizing.beginOpening(defaultSize: settings.panelDefaultSize, hasText: !model.text.isEmpty)
            let queriesAccessibility = !isNoteMode && Self.shouldQueryAccessibility(
                of: app,
                ownProcessIdentifier: ownProcessIdentifier
            )
            let mode = settings.effectivePanelScreen
            let fieldFrame = ScreenCoordinates.primaryScreenFrame.flatMap { primaryScreenFrame in
                PanelOpenPlacement.fieldFrame(
                    mode: mode,
                    isTrusted: isTrusted,
                    target: queriesAccessibility ? app : nil,
                    probe: fieldProbe,
                    observedFocus: start?.focus ?? observedFocus,
                    primaryScreenHeight: primaryScreenFrame.height
                )
            }
            let screens = NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
            let mouseLocation = NSEvent.mouseLocation
            if let screen = PanelOpenPlacement.screen(
                mode: mode,
                screens: screens,
                mouseLocation: mouseLocation,
                fieldFrame: fieldFrame,
                locateTargetWindowFrame: Self.windowFrameLocator(for: app, locate: locateTargetWindowFrame)
            ) {
                let placed = PanelOpenPlacement.frame(
                    size: sizing.openingSize(in: screen.visibleFrame),
                    on: screen,
                    mode: mode,
                    fieldFrame: fieldFrame,
                    mouseLocation: mouseLocation
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
            present(at: panel.frame)
            return
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        prepareToClose()
        hidePanel()
        model.dismiss()
        library.flush()
    }

    /// 終了の前に、書きかけを履歴へ移し、遅らせている下書きの書き出しを今行う。
    func prepareForTermination() {
        session.prepareForTermination()
        library.flush()
    }

    /// アプリが隠れたときに、動きなしでパネルを閉じて枠を本来の枠に戻す。
    func closeImmediately() {
        prepareToClose()
        hideWithoutMotion()
        model.dismiss()
        library.flush()
    }

    /// ⌘H を受け取る。アニメーションがオンで開いているときは閉じる動きのあとにアプリを隠して true を返す。
    func handleHideKey() -> Bool {
        guard settings.isPanelAnimationEnabled,
              motion.phase == .opening || motion.phase == .shown else { return false }
        prepareToClose()
        hidePanel(then: { [weak self] in self?.hideApplication() })
        model.dismiss()
        library.flush()
        return true
    }

    private func prepareToClose() {
        stopPanelEffects()
    }

    private func stopPanelEffects() {
        shaker.stop(panel)
        saveAnimation.cancel()
    }

    private func shakePanel() {
        finishSidebarSlide()
        guard PanelShake.canStart(motionPhase: motion.phase) else { return }
        shaker.shake(panel)
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
            commitKey: settings.isNoteMode ? nil : settings.commitKey,
            commitAndSendKey: settings.isNoteMode ? nil : settings.commitAndSendKey
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
            if session.isSaveAvailable {
                session.saveCurrent()
            } else {
                shakePanel()
            }
            return true
        case .newDraft:
            requestNewScratch()
            return true
        case .toggleSidebar:
            toggleSidebarAndMoveFocus()
            return true
        case .openSettings:
            openSettings()
            return true
        case .passThrough:
            return false
        }
    }

    // MARK: - クリックの操作

    /// タイトルバーの新規作成のアイコン。変換中の文字を確定してから新しい書きかけにする。
    func newDraftFromButton() {
        Self.commitMarkedText(in: panel)
        requestNewScratch()
    }

    private func requestNewScratch() {
        session.request(.newScratch)
        model.requestFocus()
    }

    /// タイトルバーの保存のアイコン。変換中の文字を確定してから下書きに保存する。
    func saveDraftFromButton() {
        Self.commitMarkedText(in: panel)
        if session.isSaveAvailable {
            session.saveCurrent()
        } else {
            shakePanel()
        }
        model.requestFocus()
    }

    /// 下の帯の「挿入」「送信」のボタン。ノートモードでは何もしない。変換中の文字を確定してから確定する。
    func commitFromButton(shouldSendAfterInsert: Bool) {
        guard !settings.isNoteMode else { return }
        Self.commitMarkedText(in: panel)
        commit(shouldSendAfterInsert: shouldSendAfterInsert)
    }

    /// サイドバーの歯車のボタンと ⌘,。パネルを閉じて(書いた文章は残る)、設定を開く処理を呼ぶ。
    func openSettings() {
        closeFromButton()
        onOpenSettings?()
    }

    /// タイトルバーのサイドバーの開閉ボタン。
    func toggleSidebarFromButton() {
        toggleSidebarAndMoveFocus()
    }

    private func toggleSidebarAndMoveFocus() {
        let shouldOpen = !sidebarModel.isOpen
        setSidebarOpen(shouldOpen)
        if shouldOpen {
            sidebarModel.focusList()
        } else {
            model.requestFocus()
        }
    }

    /// 一覧・検索欄にフォーカスがあるときに押されたキーを処理する。確定・確定+送信なら実行して `true` を返す。
    func handleKeyOutsideEditor(_ input: PanelKeyInput) -> Bool {
        switch PanelKeyResolver.actionOutsideEditor(
            for: input,
            commitKey: settings.isNoteMode ? nil : settings.commitKey,
            commitAndSendKey: settings.isNoteMode ? nil : settings.commitAndSendKey
        ) {
        case .commit:
            commit(shouldSendAfterInsert: false)
            return true
        case .commitAndSend:
            commit(shouldSendAfterInsert: true)
            return true
        default:
            return false
        }
    }

    // MARK: - サイドバー

    /// サイドバーを開閉する。パネルが開いていれば、窓の枠をサイドバーの幅だけ変える。アニメーションがオンなら滑らせて変える。
    func setSidebarOpen(_ isOpen: Bool) {
        shaker.stop(panel)
        finishSidebarSlide()
        let wasOpen = sidebarModel.isOpen
        guard isOpen != wasOpen else { return }
        guard model.isPresented else {
            sidebarModel.setOpen(isOpen)
            applyMinimumSize()
            return
        }
        if settings.isPanelAnimationEnabled, motion.phase == .shown {
            slideSidebar(open: isOpen)
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

    private func slideSidebar(open isOpen: Bool) {
        let target = isOpen
            ? SidebarLayout.expandedFrame(bodyFrame: panel.frame, visibleFrame: visibleFrameForSidebar)
            : SidebarLayout.collapsedFrame(expandedFrame: panel.frame)
        sidebarSlideGeneration += 1
        let generation = sidebarSlideGeneration
        sidebarSlide = SidebarSlide(generation: generation, frame: target, isOpen: isOpen)
        isAdjustingFrameForSidebar = true
        sidebarModel.slidingBodyWidth = isOpen ? target.width - SidebarLayout.width : target.width
        if isOpen {
            sidebarModel.setOpen(true)
        } else {
            panel.contentMinSize = SidebarLayout.minimumWindowSize(isSidebarOpen: false)
        }
        animator.animate(panel, to: target, duration: PanelMotion.duration, curve: isOpen ? .easeOut : .easeIn) { [weak self] in
            guard let self, let slide = self.sidebarSlide, slide.generation == generation else { return }
            self.sidebarSlide = nil
            self.completeSidebarSlide(isOpen: slide.isOpen)
        }
    }

    private func finishSidebarSlide() {
        guard let slide = sidebarSlide else { return }
        sidebarSlide = nil
        animator.jump(panel, to: slide.frame)
        completeSidebarSlide(isOpen: slide.isOpen)
    }

    private func completeSidebarSlide(isOpen: Bool) {
        sidebarModel.setOpen(isOpen)
        sidebarModel.slidingBodyWidth = nil
        isAdjustingFrameForSidebar = false
        applyMinimumSize()
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

    /// 閉じる前に、覚えている入力欄の位置が読めるかを確かめるか。
    static func shouldCheckTrackedField(
        target: InsertionTarget?,
        text: String,
        isTrusted: Bool,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        guard !text.isEmpty, isTrusted, let target else { return false }
        return !target.isOwnApp(ownProcessIdentifier)
    }

    func commit(shouldSendAfterInsert: Bool = false) {
        library.flush()
        let shouldCheckField = Self.shouldCheckTrackedField(
            target: model.target,
            text: model.text,
            isTrusted: permission.isTrusted,
            ownProcessIdentifier: ownProcessIdentifier
        )
        if shouldCheckField, !targetMonitor.isTrackedFieldReadable() {
            targetMonitor.rejectCurrentField()
            model.signalNoTarget()
            returnInputToPanel()
            return
        }
        performCommit(shouldSendAfterInsert: shouldSendAfterInsert)
    }

    private func performCommit(shouldSendAfterInsert: Bool) {
        let plan = session.prepareCommit {
            model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        }
        if plan == .noTarget { return }
        if plan == .emptyText {
            shakePanel()
            return
        }
        stopPanelEffects()
        finishSidebarSlide()
        hidePanel()
        library.flush()
        if case .insert(let text, let target) = plan {
            onInsertionRequested?(text, target, shouldSendAfterInsert)
        }
        Task { [weak self, performer, model] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            self?.sizing.handleCommitOutcome(outcome)
            self?.session.finishCommit(plan, outcome: outcome)
            if case .insert(let text, _) = plan,
               outcome == .notInserted,
               !model.isPresented,
               model.text == text {
                self?.reopenAfterFailedInsertion()
            }
        }
    }

    private func reopenAfterFailedInsertion() {
        open()
        targetMonitor.rejectCurrentField()
        model.signalNoTarget()
    }

    private func returnInputToPanel() {
        guard model.isPresented else { return }
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
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
        panel.makeKeyAndOrderFront(nil)
        let token = motion.beginOpening()
        pendingCloseCompletion = nil
        animator.animate(panel, to: restFrame, duration: PanelMotion.duration, curve: .easeOut) { [weak self] in
            self?.finishMotion(token)
        }
    }

    private func hidePanel(then completion: (() -> Void)? = nil) {
        finishSidebarSlide()
        guard settings.isPanelAnimationEnabled, motion.phase != .hidden else {
            hideWithoutMotion()
            completion?()
            return
        }
        if motion.phase == .closing { return }
        guard let ghost = PanelClosingGhost.make(from: panel) else {
            hideWithoutMotion()
            completion?()
            return
        }
        let wasOpening = motion.phase == .opening
        let panelFrame = wasOpening ? (restingFrame ?? panel.frame) : panel.frame
        let token = motion.beginClosing()
        pendingCloseCompletion = completion
        restingFrame = nil
        closingGhost = ghost
        ghost.orderFrontRegardless()
        panel.orderOut(nil)
        if wasOpening {
            animator.jump(panel, to: panelFrame)
        }
        endMotion()
        animator.animate(
            ghost,
            to: PanelMotion.lineFrame(of: ghost.frame),
            duration: PanelMotion.duration,
            curve: .easeIn
        ) { [weak self] in
            if let self {
                self.finishMotion(token)
            } else {
                ghost.orderOut(nil)
            }
        }
    }

    private func hideWithoutMotion() {
        finishSidebarSlide()
        discardGhost()
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        panel.orderOut(nil)
        if let frame = restingFrame {
            restingFrame = nil
            animator.jump(panel, to: frame)
        }
        endMotion()
    }

    private func finishMotion(_ token: Int) {
        guard motion.finish(token) else { return }
        switch motion.phase {
        case .shown:
            restingFrame = nil
            endMotion()
        case .hidden:
            discardGhost()
            let completion = pendingCloseCompletion
            pendingCloseCompletion = nil
            completion?()
        case .opening, .closing:
            break
        }
    }

    private func discardGhost() {
        closingGhost?.orderOut(nil)
        closingGhost = nil
    }

    private func beginMotion() {
        panel.contentMinSize = NSSize(width: 1, height: 1)
    }

    private func endMotion() {
        applyMinimumSize()
    }

    private func stopMotion() {
        guard motion.phase == .opening || motion.phase == .closing else { return }
        let wasOpening = motion.phase == .opening
        discardGhost()
        motion.hideWithoutMotion()
        pendingCloseCompletion = nil
        let frame = restingFrame ?? panel.frame
        restingFrame = nil
        if wasOpening {
            animator.jump(panel, to: frame)
        }
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(_ notification: Notification) {
        guard !isAdjustingFrameForSidebar, motion.phase != .opening, motion.phase != .closing else { return }
        liveResizeStartSize = bodySize(of: panel.frame.size)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        defer { liveResizeStartSize = nil }
        guard !isAdjustingFrameForSidebar, let startSize = liveResizeStartSize else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if motion.phase == .opening || sidebarSlide != nil {
            return frameSize
        }
        if !sender.inLiveResize, motion.phase == .shown, !isAdjustingFrameForSidebar, resizeStartSize == nil {
            resizeStartSize = bodySize(of: sender.frame.size)
        }
        let minimum = SidebarLayout.minimumWindowSize(isSidebarOpen: sidebarModel.isOpen)
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let startSize = resizeStartSize else { return }
        resizeStartSize = nil
        guard motion.phase == .shown, !isAdjustingFrameForSidebar, sidebarSlide == nil else { return }
        sizing.userDidResize(from: startSize, to: bodySize(of: panel.frame.size))
    }

    private func bodySize(of windowSize: CGSize) -> CGSize {
        SidebarLayout.bodySize(windowSize: windowSize, isSidebarOpen: sidebarModel.isOpen)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
