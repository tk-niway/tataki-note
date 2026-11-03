import Foundation

/// 起動のされ方の判定。
enum AppLaunchContext {
    /// このプロセスの環境変数。
    static let processEnvironment = ProcessInfo.processInfo.environment

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
        makeSuite: (String) -> (any SettingsStorage)? = { UserDefaults(suiteName: $0) }
    ) -> any SettingsStorage {
        guard let name = settingsSuiteName(environment: environment) else { return UserDefaults.standard }
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

    private static func isSuppressedInSuiteLaunch(unlessEnabled key: String, environment: [String: String]) -> Bool {
        #if DEBUG
        guard settingsSuiteName(environment: environment) != nil else { return false }
        return environment[key] != "enabled"
        #else
        return false
        #endif
    }

    static func isFirstLaunchTutorialSuppressed(environment: [String: String]) -> Bool {
        isSuppressedInSuiteLaunch(unlessEnabled: "TATAKINOTE_FIRST_LAUNCH_TUTORIAL", environment: environment)
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
        isSuppressedInSuiteLaunch(unlessEnabled: "TATAKINOTE_OPEN_PANEL_ON_LAUNCH", environment: environment)
    }

    static func isOpenPanelOnReopenSuppressed(environment: [String: String]) -> Bool {
        isSuppressedInSuiteLaunch(unlessEnabled: "TATAKINOTE_OPEN_PANEL_ON_REOPEN", environment: environment)
    }

    enum UpdaterKind: Equatable {
        case sparkle
        case inert
        case preview
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func updaterKind(
        environment: [String: String],
        isDebugBuild: Bool = AppLaunchContext.isDebugBuild
    ) -> UpdaterKind {
        if isRunningUnitTests(environment: environment) { return .inert }
        guard isDebugBuild else { return .sparkle }
        return environment["TATAKINOTE_UPDATE_OVERRIDE"] == "available" ? .preview : .inert
    }

    static func shouldOfferMoveToApplications(
        environment: [String: String],
        isDebugBuild: Bool = AppLaunchContext.isDebugBuild
    ) -> Bool {
        if isRunningUnitTests(environment: environment) { return false }
        guard isDebugBuild else { return true }
        return environment["TATAKINOTE_MOVE_PROMPT"] == "enabled"
    }
}
