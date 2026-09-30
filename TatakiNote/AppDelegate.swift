import AppKit
import KeyboardShortcuts

/// @note p0-1
enum AppLaunchContext {
    /// @note p0-2
    static func isRunningUnitTests(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    /// @note p0-3
    static func shouldRegisterHotkeys(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    /// @note p0-4
    static func settingsSuiteName(environment: [String: String]) -> String? {
        #if DEBUG
        guard let name = environment["TATAKINOTE_SETTINGS_SUITE"], !name.isEmpty else { return nil }
        return name
        #else
        return nil
        #endif
    }

    /// @note p0-5
    static func settingsDefaults(
        environment: [String: String],
        makeSuite: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) -> UserDefaults {
        guard let name = settingsSuiteName(environment: environment) else { return .standard }
        guard let suite = makeSuite(name) else {
            preconditionFailure("設定の保存先の suite「\(name)」を作れません")
        }
        // @note p0-6
        do {
            try SettingsSeed.apply(environment: environment, to: suite)
        } catch {
            preconditionFailure("\(SettingsSeed.environmentKey) を読めません: \(error)")
        }
        return suite
    }

    /// @note p0-7
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

    /// @note p0-8
    static func accessibilityPermission(environment: [String: String]) -> AccessibilityPermissionChecking {
        guard let isTrusted = accessibilityOverride(environment: environment) else {
            return SystemAccessibilityPermission()
        }
        return OverriddenAccessibilityPermission(isTrusted: isTrusted)
    }

    /// @note p0-9
    static func shouldPresentPermissionGuideOnLaunch(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    /// @note p0-10
    static func shouldWatchFocusedElement(environment: [String: String]) -> Bool {
        !isRunningUnitTests(environment: environment)
    }

    /// @note p0-11
    static func loginItemService(environment: [String: String]) -> LoginItemService {
        #if DEBUG
        if environment["TATAKINOTE_LOGIN_ITEM_OVERRIDE"] == "memory" {
            return InMemoryLoginItemService()
        }
        #endif
        return MainAppLoginItemService()
    }

    /// @note p0-12
    static func shouldOpenSettingsOnReopen(hidesMenuBarIcon: Bool) -> Bool {
        hidesMenuBarIcon
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// @note p0-13
    let settings = AppSettings(
        store: SettingsStore(defaults: AppLaunchContext.settingsDefaults(environment: ProcessInfo.processInfo.environment))
    )

    /// @note p0-14
    let targetTracker = FrontmostAppTracker()

    /// @note p0-15
    let permission = AppLaunchContext.accessibilityPermission(environment: ProcessInfo.processInfo.environment)

    /// @note p0-16
    private(set) lazy var permissionGuide = PermissionGuideWindowController(
        model: PermissionGuideModel(permission: permission),
        settings: settings
    )

    /// @note p0-17
    private(set) lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        launchAtLogin: LaunchAtLoginModel(
            service: AppLaunchContext.loginItemService(environment: ProcessInfo.processInfo.environment)
        ),
        // @note p0-18
        appInfo: AppInfoModel(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            permissionStatus: PermissionGuideModel(permission: permission)
        ),
        // @note p0-19
        panelDefaultSize: PanelDefaultSizeModel(
            settings: settings,
            currentPanelSize: { [weak self] in self?.panelController.heldPanelSize }
        )
    )

    // @note p0-20
    private(set) lazy var panelController: PanelController = {
        let controller = PanelController(settings: self.settings, targetTracker: self.targetTracker, permission: self.permission)
        // @note p0-21
        controller.onPermissionDenied = { [weak self] in
            self?.permissionGuide.show(reason: .commitDenied)
        }
        return controller
    }()

    /// @note p0-22
    private var focusedElementWatcher: FocusedElementWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        if AppLaunchContext.shouldRegisterHotkeys(environment: environment) {
            KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
                self?.panelController.toggle()
            }
        }
        if AppLaunchContext.shouldWatchFocusedElement(environment: environment) {
            // @note p0-23
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
            permissionGuide.showOnLaunchIfNeeded()
        }
    }

    // @note p0-24
    func applicationDidHide(_ notification: Notification) {
        panelController.close()
    }

    // @note p0-25
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppLaunchContext.shouldOpenSettingsOnReopen(hidesMenuBarIcon: settings.hidesMenuBarIcon) {
            settingsWindow.show()
        }
        return false
    }
}
