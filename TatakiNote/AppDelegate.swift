import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings(
        store: SettingsStore(defaults: AppLaunchContext.settingsDefaults(environment: AppLaunchContext.processEnvironment))
    )

    let targetTracker = FrontmostAppTracker()

    let permission = AppLaunchContext.accessibilityPermission(environment: AppLaunchContext.processEnvironment)

    private(set) lazy var permissionGuide: PermissionGuideWindowController = {
        let controller = PermissionGuideWindowController(
            model: PermissionGuideModel(permission: self.permission),
            settings: self.settings
        )
        controller.onProceedToTutorial = { [weak self] in
            self?.tutorial.show()
        }
        return controller
    }()

    private(set) lazy var tutorial = TutorialWindowController(
        settings: settings,
        panelModel: panelController.model,
        draftSession: panelController.session
    )

    private(set) lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(
            settings: self.settings,
            launchAtLogin: LaunchAtLoginModel(
                service: AppLaunchContext.loginItemService(environment: AppLaunchContext.processEnvironment)
            ),
            appInfo: AppInfoModel(
                infoDictionary: Bundle.main.infoDictionary ?? [:],
                permissionStatus: PermissionGuideModel(permission: self.permission),
                onOpenTutorial: { [weak self] in self?.tutorial.show() }
            ),
            panelDefaultSize: PanelDefaultSizeModel(
                settings: self.settings,
                currentPanelSize: { [weak self] in self?.panelController.heldPanelSize }
            ),
            library: self.library,
            updates: self.updates
        )
        controller.onDidClose = { [weak self] in
            self?.panelController.settingsWindowDidClose()
        }
        return controller
    }()

    let webContentExposer = WebContentExposer()

    private(set) lazy var library = DraftLibrary(
        store: DraftLibraryStore(directory: AppLaunchContext.dataDirectory(environment: AppLaunchContext.processEnvironment)),
        historyLimit: settings.historyLimit,
        historyRetention: settings.historyRetention,
        writer: BackgroundDraftLibraryWriter()
    )

    private(set) lazy var panelController: PanelController = {
        let controller = PanelController(
            settings: self.settings,
            targetTracker: self.targetTracker,
            permission: self.permission,
            exposeWebContent: { [webContentExposer] in webContentExposer.expose($0) },
            openingLookup: BackgroundOpeningTargetLookup(exposer: webContentExposer),
            library: self.library
        )
        controller.isTargetLookupDisabled = AppLaunchContext.isInsertionTargetDisabled(
            environment: AppLaunchContext.processEnvironment
        )
        controller.onPermissionDenied = { [weak self] in
            self?.permissionGuide.show(reason: .commitDenied)
        }
        controller.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        controller.targetOverride = { [weak self] in
            self?.tutorial.practiceTarget()
        }
        controller.isOwnTargetAvailable = { [weak self] in
            self?.tutorial.window?.isVisible == true
        }
        controller.onInsertionRequested = { [weak self] text, target, sendsAfterInsert in
            self?.tutorial.handleInsertionRequested(text: text, target: target, sendsAfterInsert: sendsAfterInsert)
        }
        return controller
    }()

    private var focusedElementWatcher: FocusedElementWatcher?

    private(set) lazy var updates: UpdateModel = {
        let model = UpdateModel(
            settings: settings,
            updater: AppDelegate.makeUpdater(kind: AppLaunchContext.updaterKind(environment: AppLaunchContext.processEnvironment))
        )
        model.onWillRelaunch = { [weak self] in self?.markRelaunching() }
        return model
    }()

    private lazy var networkMonitor: NetworkReachability = NetworkPathMonitor()

    private var wakeObserver: NSObjectProtocol?

    private lazy var updateBadge = UpdateBadgeController(
        updates: updates,
        setBadgeLabel: { NSApp.dockTile.badgeLabel = $0 }
    )

    private lazy var dockIcon = DockIconController(
        settings: settings,
        setActivationPolicy: { NSApp.setActivationPolicy($0) },
        didHideIcon: { [weak self] in self?.settingsWindow.bringToFrontIfVisible() },
        didApplyPolicy: { [weak self] in self?.updateBadge.reapply() }
    )

    private static func makeUpdater(kind: AppLaunchContext.UpdaterKind) -> UpdaterDriving {
        switch kind {
        case .sparkle:
            #if canImport(Sparkle)
            return SparkleUpdaterDriver()
            #else
            return InertUpdater()
            #endif
        case .preview:
            #if DEBUG
            return PreviewUpdater()
            #else
            return InertUpdater()
            #endif
        case .inert:
            return InertUpdater()
        }
    }

    private lazy var quitConfirmation = QuitConfirmationController(
        model: QuitConfirmationModel(settings: settings, terminate: { NSApp.terminate(nil) }),
        settings: settings,
        isRecordingShortcut: { event in
            ShortcutRecordingMonitorView.isRecordingAnywhere
                || QuitConfirmationController.isKeyboardShortcutsRecorderFocused(in: event.window)
        },
        isPanelCommitKey: { [weak self] event in
            guard let self else { return false }
            let input = PanelKeyInput(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                hasMarkedText: PromptPanel.firstResponderHasMarkedText(event.window?.firstResponder),
                characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
            )
            return QuitConfirmation.isPanelCommitKey(
                input,
                isPanelKey: event.window === self.panelController.panel,
                commitKey: self.settings.commitKey,
                commitAndSendKey: self.settings.commitAndSendKey
            )
        }
    )

    private(set) var terminationReason: TerminationReason = .normal

    private let relaunchDraftStore = RelaunchDraftStore(
        directory: AppLaunchContext.dataDirectory(environment: AppLaunchContext.processEnvironment)
    )

    /// 書きかけを残して開き直すために、終了の理由を記録して終了する。
    func terminateForRelaunch() {
        markRelaunching()
        NSApp.terminate(nil)
    }

    /// 次の終了が開き直しのためだと記録する。
    func markRelaunching() {
        terminationReason = .relaunch
    }

    private lazy var moveToApplications = MoveToApplicationsController(
        settings: settings,
        terminateForRelaunch: { [weak self] in self?.terminateForRelaunch() }
    )

    private var isConfirmingQuit: Bool {
        quitConfirmation.model.isConfirming
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppLaunchContext.processEnvironment
        if AppLaunchContext.shouldApplyDockIcon(environment: environment) {
            dockIcon.start()
            updateBadge.start()
        }
        if !AppLaunchContext.isRunningUnitTests(environment: environment) {
            quitConfirmation.start()
            if AppLaunchContext.shouldOfferMoveToApplications(environment: environment),
               moveToApplications.offerIfNeeded() {
                return
            }
            panelController.restoreRelaunchDraft(from: relaunchDraftStore)
        }
        if AppLaunchContext.shouldRegisterHotkeys(environment: environment) {
            ReservedPanelKeys.apply(
                to: settings,
                hotkey: PanelShortcut.currentHotkey(),
                defaultHotkey: KeyboardShortcuts.Name.togglePanel.initialShortcut.map { PanelShortcut($0) },
                resetHotkey: { KeyboardShortcuts.reset(.togglePanel) }
            )
            settings.registerDefaultCommitKeysIfBothMissing(hotkey: PanelShortcut.currentHotkey())
            KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
                guard let self, AppOpenRequest.allowsPanelToggle(isConfirmingQuit: self.isConfirmingQuit) else { return }
                self.panelController.toggle()
            }
        }
        if AppLaunchContext.shouldWatchFocusedElement(environment: environment) {
            let watcher = FocusedElementWatcher(
                settings: settings,
                panelModel: panelController.model,
                permission: permission,
                exposeWebContent: { [webContentExposer] in webContentExposer.expose($0) },
                onShow: { [weak self] focus in
                    guard let self, AppOpenRequest.allowsPanelToggle(isConfirmingQuit: self.isConfirmingQuit) else { return }
                    self.panelController.open(observedFocus: focus)
                }
            )
            watcher.start()
            focusedElementWatcher = watcher
        }
        if AppLaunchContext.shouldPresentPermissionGuideOnLaunch(environment: environment) {
            let presentation = presentOnLaunch(environment: environment)
            if AppOpenRequest.shouldOpenPanelOnLaunch(
                presentation: presentation,
                isLoginItemLaunch: Self.isLoginItemLaunch(),
                isSuppressed: AppLaunchContext.isOpenPanelOnLaunchSuppressed(environment: environment)
            ) {
                panelController.openWithoutTarget()
            }
        }
        if !AppLaunchContext.isRunningUnitTests(environment: environment) {
            startUpdates()
        }
    }

    private func startUpdates() {
        updates.start()
        networkMonitor.start { [weak self] isOnline in
            self?.updates.networkDidChange(isOnline: isOnline)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updates.evaluate()
            }
        }
    }

    private func presentOnLaunch(environment: [String: String]) -> LaunchPresentation {
        let presentation = FirstLaunchFlow.resolveOnLaunch(
            settings: settings,
            isTrusted: permission.isTrusted,
            isSuppressed: AppLaunchContext.isFirstLaunchTutorialSuppressed(environment: environment)
        )
        switch presentation {
        case .nothing:
            break
        case .tutorial:
            tutorial.show()
        case .permissionGuide(let reason):
            permissionGuide.show(reason: reason)
        }
        return presentation
    }

    private static func isLoginItemLaunch() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return AppOpenRequest.isLoginItemLaunch(
            eventID: event?.eventID,
            propData: event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        )
    }

    func applicationDidHide(_ notification: Notification) {
        panelController.closeImmediately()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitConfirmation.shouldTerminate(
            currentEvent: NSApp.currentEvent,
            isQuitAppleEvent: QuitConfirmation.isQuitAppleEvent(eventID: NSAppleEventManager.shared().currentAppleEvent?.eventID)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController.prepareForTermination(reason: terminationReason, store: relaunchDraftStore)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppOpenRequest.shouldOpenPanelOnReopen(
            isPanelPresented: panelController.model.isPresented,
            isConfirmingQuit: isConfirmingQuit,
            isSuppressed: AppLaunchContext.isOpenPanelOnReopenSuppressed(environment: AppLaunchContext.processEnvironment)
        ) {
            panelController.openWithoutTarget()
        }
        return false
    }
}
