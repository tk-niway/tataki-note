import AppKit
import SwiftUI

/// パネルの開け閉め。
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    /// 入力パネルの窓。
    let panel: PromptPanel
    private let settings: AppSettings
    private let hideApplication: () -> Void
    private let targetTracker: FrontmostAppTracker
    private let permission: AccessibilityPermissionChecking
    private let openFrameResolver: PanelOpenFrameResolver
    private let exposeWebContent: (InsertionTarget) -> Void
    private let ownProcessIdentifier: pid_t
    private let library: DraftLibrary
    private let targetMonitor: InsertionTargetMonitor
    private let outlineController: InsertionTargetOutlineController
    private let sharingAnchorRegistry = SharingAnchorRegistry()

    let session: DraftSession
    let sidebarModel: SidebarModel
    let saveAnimation: SaveAnimationModel

    let sizeController: PanelSizeController

    private let motionController: PanelMotionController

    private let feedback: PanelFeedback

    private let exportSharing: PanelExportSharing

    private let commitFlow: PanelCommitFlow

    var heldPanelSize: CGSize? { sizeController.sizing.heldSize }

    var onPermissionDenied: (() -> Void)? {
        get { commitFlow.onPermissionDenied }
        set { commitFlow.onPermissionDenied = newValue }
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

    /// 設定を開く処理。
    var onOpenSettings: (() -> Void)?

    /// 確定で挿入することになったとき、パネルを閉じた後・挿入の前に、文章・挿入先・送信もするかを知らせる。
    var onInsertionRequested: ((String, InsertionTarget, Bool) -> Void)? {
        get { commitFlow.onInsertionRequested }
        set { commitFlow.onInsertionRequested = newValue }
    }

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
        beep: @escaping () -> Void = { NSSound.beep() },
        hideApplication: @escaping () -> Void = { NSApp.hide(nil) },
        makeTargetMonitor: ((PanelModel) -> InsertionTargetMonitor)? = nil,
        exportChooser: ExportDestinationChoosing = SavePanelDestinationChooser(),
        writeTextFile: @escaping (String, URL) throws -> Void = TextFileWriter.write,
        sharer: TextSharing? = nil,
        presentExportFailure: ((String, NSWindow?, @escaping () -> Void) -> Void)? = nil
    ) {
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultSize))
        self.model = model
        self.panel = panel
        self.settings = settings
        self.hideApplication = hideApplication
        self.targetTracker = targetTracker
        self.permission = permission
        self.openFrameResolver = PanelOpenFrameResolver(
            fieldProbe: fieldProbe,
            locateTargetWindowFrame: locateTargetWindowFrame,
            ownProcessIdentifier: ownProcessIdentifier
        )
        self.exposeWebContent = exposeWebContent
        self.ownProcessIdentifier = ownProcessIdentifier
        self.library = library
        let session = DraftSession(
            panel: model,
            library: library,
            ownProcessIdentifier: ownProcessIdentifier,
            newDraftMode: { [settings] in settings.newDraftMode }
        )
        let targetMonitor = makeTargetMonitor?(model) ?? InsertionTargetMonitor(
            panelModel: model,
            probe: fieldProbe,
            ownProcessIdentifier: ownProcessIdentifier,
            exposeWebContent: exposeWebContent,
            isOutlineEnabled: { [settings] in PanelController.isOutlineTrackingEnabled(settings: settings) }
        )
        self.targetMonitor = targetMonitor
        self.outlineController = InsertionTargetOutlineController(
            outline: targetMonitor.outline,
            settings: settings,
            panelModel: model,
            panel: panel,
            session: session
        )
        self.session = session
        let sidebarModel = SidebarModel(settings: settings, library: library, session: session)
        self.sidebarModel = sidebarModel
        let sizeController = PanelSizeController(panel: panel, sidebarModel: sidebarModel, animator: animator)
        self.sizeController = sizeController
        self.motionController = PanelMotionController(
            panel: panel,
            animator: animator,
            restoreMinimumSize: { [sizeController] in sizeController.applyMinimumSize() }
        )
        self.saveAnimation = saveAnimation
        self.feedback = PanelFeedback(
            panel: panel,
            model: model,
            session: session,
            sidebarModel: sidebarModel,
            library: library,
            saveAnimation: saveAnimation,
            settings: settings,
            shaker: shaker,
            beep: beep
        )
        self.exportSharing = PanelExportSharing(
            model: model,
            panel: panel,
            exporter: TextExporter(settings: settings, chooser: exportChooser, write: writeTextFile),
            sharer: sharer ?? SharingServicePresenter(panel: panel, anchorRegistry: sharingAnchorRegistry),
            presentFailure: presentExportFailure ?? { message, window, completion in
                ExportFailureAlert.show(message: message, attachedTo: window, completion: completion)
            }
        )
        self.commitFlow = PanelCommitFlow(
            model: model,
            session: session,
            library: library,
            permission: permission,
            inserter: inserter,
            targetMonitor: targetMonitor,
            sizing: sizeController.sizing,
            ownProcessIdentifier: ownProcessIdentifier
        )
        super.init()

        let hostingView = NSHostingView(
            rootView: PanelView(
                model: model,
                settings: settings,
                onKeyInput: { [weak self] in self?.handleKey($0) ?? false },
                onCommand: { [weak self] in self?.perform($0, from: .button) },
                session: session,
                sidebarModel: sidebarModel,
                saveAnimation: saveAnimation,
                sharingAnchorRegistry: sharingAnchorRegistry
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(PanelMetrics.defaultSize)
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.handleKey($0) ?? false }
        panel.onHideKey = { [weak self] in self?.handleHideKey() ?? false }
        panel.onKeyDownOutsideEditor = { [weak self] in self?.handleKeyOutsideEditor($0) ?? false }
        sizeController.applyMinimumSize()
        configureSidebarModel()
        observeBodyFocusRequests()
        feedback.startObserving()
        connectParts()
        targetMonitor.onFieldAdopted = { [weak self] in self?.handleFieldAdopted() }
    }

    private func connectParts() {
        exportSharing.onEmptyInput = { [weak self] in self?.signalEmptyInput() }
        exportSharing.onToast = { [weak self] message, style in self?.feedback.showToast(message, style: style) }
        exportSharing.onReturnInput = { [weak self] in self?.returnInputToPanel() }
        commitFlow.onEmptyInput = { [weak self] in self?.signalEmptyInput() }
        commitFlow.onReturnInput = { [weak self] in self?.returnInputToPanel() }
        commitFlow.onHide = { [weak self] in
            self?.feedback.stopEffects()
            self?.hidePanel()
        }
        commitFlow.onReopen = { [weak self] in self?.open() }
    }

    /// 他のアプリの入力欄をクリックして挿入先が移ったときに、キー入力をパネルへ戻すか。インサートの書きかけだけ戻す。
    static func shouldReturnInputAfterFieldAdopted(mode: DraftMode) -> Bool {
        mode == .insert
    }

    private func handleFieldAdopted() {
        guard Self.shouldReturnInputAfterFieldAdopted(mode: session.mode) else { return }
        returnInputToPanel()
    }

    /// 挿入先の入力欄の位置を読み、枠線の矩形を計算し続けるか。書きかけのモードには関わらない。
    static func isOutlineTrackingEnabled(settings: AppSettings) -> Bool {
        settings.isInsertionTargetOutlineShown
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
        sidebarModel.exportText = { [weak self] in self?.exportSharing.exportText($0) }
        sidebarModel.shareText = { [weak self] in self?.exportSharing.share($0, from: .pointer) }
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

    /// 挿入先を探さずにパネルを開く。開いているときは何もしない。
    func openWithoutTarget() {
        guard !model.isPresented else { return }
        open(looksUpTarget: false)
    }

    func open(observedFocus: ObservedFocus? = nil, looksUpTarget: Bool = true) {
        let app = (isTargetLookupDisabled || !looksUpTarget) ? nil : (targetOverride?() ?? targetTracker.currentTarget())
        settings.refreshKeyDisplayTexts()
        let wasPresented = model.isPresented
        var start: InsertionTargetStart?
        let isTrusted = permission.isTrusted
        if !wasPresented {
            if let app,
               PanelOpenFrameResolver.shouldExposeWebContent(
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
            library.pruneExpiredHistory()
            sidebarModel.discardPendingFocusRequests()
            motionController.stop()
            sizeController.sizing.beginOpening(defaultSize: settings.panelDefaultSize, hasText: !model.text.isEmpty)
            let openingFrame = openFrameResolver.frame(
                target: app,
                mode: settings.panelScreen,
                isTrusted: isTrusted,
                observedFocus: start?.focus ?? observedFocus,
                isSidebarOpen: sidebarModel.isOpen,
                openingSize: { [sizeController] in sizeController.sizing.openingSize(in: $0) }
            )
            if let frame = openingFrame {
                sizeController.applyMinimumSize()
                panel.setFrame(frame, display: false)
            } else {
                sizeController.applyMinimumSize()
                panel.center()
            }
            motionController.present(at: panel.frame, isAnimationEnabled: settings.isAnimationEnabled)
            return
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        dismiss(.animated)
    }

    /// 終了の理由に応じて書きかけを扱い、遅らせている下書きの書き出しを今行う。
    func prepareForTermination(reason: TerminationReason, store: RelaunchDraftStore) {
        session.prepareForTermination(reason: reason, store: store)
        library.finishPendingWrites()
    }

    /// 開き直しで残した書きかけがあれば、パネルを開かずに戻す。
    func restoreRelaunchDraft(from store: RelaunchDraftStore) {
        guard let draft = store.take() else { return }
        session.restore(draft)
    }

    /// アプリが隠れたときに、動きなしでパネルを閉じて枠を本来の枠に戻す。
    func closeImmediately() {
        dismiss(.immediately)
    }

    /// ⌘H を受け取る。アニメーションがオンで開いているときは閉じる動きのあとにアプリを隠して true を返す。
    func handleHideKey() -> Bool {
        guard settings.isAnimationEnabled,
              motionController.phase == .opening || motionController.phase == .shown else { return false }
        dismiss(.animatedThenHideApplication)
        return true
    }

    private enum Dismissal {
        case animated
        case animatedThenHideApplication
        case immediately
    }

    private func dismiss(_ dismissal: Dismissal) {
        feedback.stopEffects()
        switch dismissal {
        case .animated: hidePanel()
        case .animatedThenHideApplication: hidePanel(then: { [weak self] in self?.hideApplication() })
        case .immediately: hideWithoutMotion()
        }
        model.dismiss()
        library.flush()
    }

    private func hidePanel(then completion: (() -> Void)? = nil) {
        sizeController.finishSidebarSlide()
        motionController.hide(isAnimationEnabled: settings.isAnimationEnabled, then: completion)
    }

    private func hideWithoutMotion() {
        sizeController.finishSidebarSlide()
        motionController.hideWithoutMotion()
    }

    private func signalEmptyInput() {
        sizeController.finishSidebarSlide()
        feedback.signalEmptyInput(motionPhase: motionController.phase)
    }

    func toggle() {
        if model.isPresented {
            close()
        } else {
            open()
        }
    }

    static func commitMarkedText(in window: NSWindow) {
        (window.firstResponder as? PromptTextView)?.commitMarkedText()
    }

    func handleKey(_ input: PanelKeyInput) -> Bool {
        let action = PanelKeyResolver.action(
            for: input,
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey,
            mode: session.mode
        )
        if let command = action.command {
            return perform(command, from: .key)
        }
        return action == .insertNewline && insertNewlineInEditor()
    }

    /// パネルの操作を行う。キーでもボタンでも、ここを通る。行ったら `true` を返す。
    @discardableResult
    func perform(_ command: PanelCommand, from source: PanelCommandSource) -> Bool {
        guard command.isAvailable(in: session.mode, from: source) else { return false }
        if command.commitsMarkedTextFirst(from: source) {
            Self.commitMarkedText(in: panel)
        }
        switch command {
        case .close: close()
        case .commit: commit(shouldSendAfterInsert: false)
        case .commitAndSend: commit(shouldSendAfterInsert: true)
        case .openSearch: openSearch()
        case .saveDraft: saveDraftOrSignalEmpty()
        case .newDraft: requestNewScratch()
        case .toggleMode: session.toggleMode()
        case .switchToInsert: session.switchToInsert()
        case .toggleSidebar: toggleSidebarAndMoveFocus()
        case .openSettings: onOpenSettings?()
        case .exportToFile: exportSharing.exportCurrentText()
        case .share: exportSharing.shareCurrentText()
        }
        if command.requestsEditorFocusAfterward(from: source) {
            model.requestFocus()
        }
        return true
    }

    private func openSearch() {
        if !sidebarModel.isOpen {
            setSidebarOpen(true)
        }
        sidebarModel.openForSearch()
    }

    private func saveDraftOrSignalEmpty() {
        if session.isSaveAvailable {
            session.saveCurrent()
        } else {
            signalEmptyInput()
        }
    }

    private func insertNewlineInEditor() -> Bool {
        guard let editor = panel.firstResponder as? PromptTextView else { return false }
        editor.insertNewline(nil)
        return true
    }

    // MARK: - クリックの操作

    private func requestNewScratch() {
        session.request(.newScratch)
        model.requestFocus()
    }

    /// 設定ウィンドウが閉じたときに呼ぶ。パネルが開いていれば、キー入力をパネルへ戻す。
    func settingsWindowDidClose() {
        returnInputToPanel()
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
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey,
            mode: session.mode
        ) {
        case .commit:
            return perform(.commit, from: .key)
        case .commitAndSend:
            return perform(.commitAndSend, from: .key)
        default:
            return false
        }
    }

    // MARK: - サイドバー

    /// サイドバーを開閉する。パネルが開いていれば、窓の枠をサイドバーの幅だけ変える。アニメーションがオンなら滑らせて変える。
    func setSidebarOpen(_ isOpen: Bool) {
        feedback.stopShaking()
        sizeController.setSidebarOpen(
            isOpen,
            isPanelPresented: model.isPresented,
            isAnimationEnabled: settings.isAnimationEnabled,
            motionPhase: motionController.phase
        )
    }

    // MARK: - 確定

    func commit(shouldSendAfterInsert: Bool = false) {
        commitFlow.commit(shouldSendAfterInsert: shouldSendAfterInsert)
    }

    private func returnInputToPanel() {
        guard model.isPresented else { return }
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
    }

    func windowWillClose(_ notification: Notification) {
        model.dismiss()
    }

    // MARK: - 大きさ

    func windowWillStartLiveResize(_ notification: Notification) {
        sizeController.windowWillStartLiveResize(motionPhase: motionController.phase)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        sizeController.windowDidEndLiveResize()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        sizeController.windowWillResize(sender, to: frameSize, motionPhase: motionController.phase)
    }

    func windowDidResize(_ notification: Notification) {
        sizeController.windowDidResize(motionPhase: motionController.phase)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
