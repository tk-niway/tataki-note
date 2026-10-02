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

    static func shouldOpenSettingsOnReopen(hidesMenuBarIcon: Bool) -> Bool {
        hidesMenuBarIcon
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
        panelModel: panelController.model
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
        )
    )

    private(set) lazy var panelController: PanelController = {
        let controller = PanelController(settings: self.settings, targetTracker: self.targetTracker, permission: self.permission)
        controller.onPermissionDenied = { [weak self] in
            self?.permissionGuide.show(reason: .commitDenied)
        }
        controller.targetOverride = { [weak self] in
            self?.tutorial.practiceTarget()
        }
        controller.onInsertionRequested = { [weak self] text, target in
            self?.tutorial.handleInsertionRequested(text: text, target: target)
        }
        return controller
    }()

    private var focusedElementWatcher: FocusedElementWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        if AppLaunchContext.shouldRegisterHotkeys(environment: environment) {
            KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
                self?.panelController.toggle()
            }
        }
        if AppLaunchContext.shouldWatchFocusedElement(environment: environment) {
            let watcher = FocusedElementWatcher(
                settings: settings,
                panelModel: panelController.model,
                permission: permission,
                onShow: { [weak self] in self?.panelController.open() }
            )
            watcher.start()
            focusedElementWatcher = watcher
        }
        if AppLaunchContext.shouldPresentPermissionGuideOnLaunch(environment: environment) {
            presentOnLaunch(environment: environment)
        }
    }

    private func presentOnLaunch(environment: [String: String]) {
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
    }

    func applicationDidHide(_ notification: Notification) {
        panelController.close()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppLaunchContext.shouldOpenSettingsOnReopen(hidesMenuBarIcon: settings.hidesMenuBarIcon) {
            settingsWindow.show()
        }
        return false
    }
}
