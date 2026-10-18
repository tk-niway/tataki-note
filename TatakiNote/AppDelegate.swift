import AppKit
import KeyboardShortcuts

/// 起動のされ方の判定。
enum AppLaunchContext {
    static func isRunningUnitTests(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    static func shouldRegisterHotkeys(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    static func settingsSuiteName(environment: [String: String]) -> String? {
        #if DEBUG
        guard let name = environment["TATAKINOTE_SETTINGS_SUITE"], !name.isEmpty else { return nil }
        return name
        #else
        return nil
        #endif
    }

    static func settingsDefaults(
        environment: [String: String],
        makeSuite: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) -> UserDefaults {
        guard let name = settingsSuiteName(environment: environment) else { return .standard }
        guard let suite = makeSuite(name) else {
            preconditionFailure("設定の保存先の suite「\(name)」を作れません")
        }
        do {
            try SettingsSeed.apply(environment: environment, to: suite)
        } catch {
            preconditionFailure("\(SettingsSeed.environmentKey) を読めません: \(error)")
        }
        return suite
    }

    static func dataDirectory(
        environment: [String: String],
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL? {
        if isRunningUnitTests(environment: environment) { return nil }
        #if DEBUG
        if let path = environment["TATAKINOTE_DATA_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let suite = settingsSuiteName(environment: environment) {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("TatakiNote-\(suite)", isDirectory: true)
        }
        #endif
        let folderName = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? "TatakiNote"
        return URL.applicationSupportDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func accessibilityOverride(environment: [String: String]) -> Bool? {
        #if DEBUG
        switch environment["TATAKINOTE_ACCESSIBILITY_OVERRIDE"] {
        case "trusted":
            return true
        case "untrusted":
            return false
        default:
            return nil
        }
        #else
        return nil
        #endif
    }

    static func accessibilityPermission(environment: [String: String]) -> AccessibilityPermissionChecking {
        guard let isTrusted = accessibilityOverride(environment: environment) else {
            return SystemAccessibilityPermission()
        }
        return OverriddenAccessibilityPermission(isTrusted: isTrusted)
    }

    static func shouldPresentPermissionGuideOnLaunch(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    static func isFirstLaunchTutorialSuppressed(environment: [String: String]) -> Bool {
        #if DEBUG
        guard settingsSuiteName(environment: environment) != nil else { return false }
        return environment["TATAKINOTE_FIRST_LAUNCH_TUTORIAL"] != "enabled"
        #else
        return false
        #endif
    }

    static func shouldWatchFocusedElement(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    static func loginItemService(environment: [String: String]) -> LoginItemService {
        #if DEBUG
        if environment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] == "memory" {
            return InMemoryLoginItemService()
        }
        #endif
        return MainAppLoginItemService()
    }

    static func isInsertionTargetDisabled(environment: [String: String]) -> Bool {
        #if DEBUG
        return environment["TATAKINOTE_INSERTION_TARGET"] == "none"
        #else
        return false
        #endif
    }

    static func shouldApplyDockIcon(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    static func isOpenPanelOnLaunchSuppressed(environment: [String: String]) -> Bool {
        #if DEBUG
        guard settingsSuiteName(environment: environment) != nil else { return false }
        return environment["TATAKINOTE_OPEN_PANEL_ON_LAUNCH"] != "enabled"
        #else
        return false
        #endif
    }

    static func isOpenPanelOnReopenSuppressed(environment: [String: String]) -> Bool {
        #if DEBUG
        guard settingsSuiteName(environment: environment) != nil else { return false }
        return environment["TATAKINOTE_OPEN_PANEL_ON_REOPEN"] != "enabled"
        #else
        return false
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings(
        store: SettingsStore(defaults: AppLaunchContext.settingsDefaults(environment: ProcessInfo.processInfo.environment))
    )

    let targetTracker = FrontmostAppTracker()

    let permission = AppLaunchContext.accessibilityPermission(environment: ProcessInfo.processInfo.environment)

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

    private(set) lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        launchAtLogin: LaunchAtLoginModel(
            service: AppLaunchContext.loginItemService(environment: ProcessInfo.processInfo.environment)
        ),
        appInfo: AppInfoModel(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            permissionStatus: PermissionGuideModel(permission: permission),
            onOpenTutorial: { [weak self] in self?.tutorial.show() }
        ),
        panelDefaultSize: PanelDefaultSizeModel(
            settings: settings,
            currentPanelSize: { [weak self] in self?.panelController.heldPanelSize }
        ),
        library: library
    )

    let webContentExposer = WebContentExposer()

    private(set) lazy var library = DraftLibrary(
        store: DraftLibraryStore(directory: AppLaunchContext.dataDirectory(environment: ProcessInfo.processInfo.environment)),
        historyLimit: settings.historyLimit
    )

    private(set) lazy var panelController: PanelController = {
        let controller = PanelController(
            settings: self.settings,
            targetTracker: self.targetTracker,
            permission: self.permission,
            exposeWebContent: { [webContentExposer] in webContentExposer.expose($0) },
            library: self.library
        )
        controller.isTargetLookupDisabled = AppLaunchContext.isInsertionTargetDisabled(
            environment: ProcessInfo.processInfo.environment
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

    private lazy var dockIcon = DockIconController(
        settings: settings,
        setActivationPolicy: { NSApp.setActivationPolicy($0) },
        didHideIcon: { [weak self] in self?.settingsWindow.bringToFrontIfVisible() }
    )

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

    private var isConfirmingQuit: Bool {
        quitConfirmation.model.isConfirming
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        if AppLaunchContext.shouldApplyDockIcon(environment: environment) {
            dockIcon.start()
        }
        if !AppLaunchContext.isRunningUnitTests(environment: environment) {
            quitConfirmation.start()
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
        panelController.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppOpenRequest.shouldOpenPanelOnReopen(
            isPanelPresented: panelController.model.isPresented,
            isConfirmingQuit: isConfirmingQuit,
            isSuppressed: AppLaunchContext.isOpenPanelOnReopenSuppressed(environment: ProcessInfo.processInfo.environment)
        ) {
            panelController.openWithoutTarget()
        }
        return false
    }
}
