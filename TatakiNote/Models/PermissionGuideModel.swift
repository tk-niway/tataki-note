import Observation

/// 案内を開いた理由。
enum PermissionGuideReason: Equatable, Sendable {
    case launch
    case commitDenied
    case firstLaunch
}

/// 案内に何を表示するか。
enum PermissionGuideState: Equatable {
    case granted
    case notGranted(PermissionGuideReason)
    case readyForTutorial
}

/// 許可の案内に出すボタン。
enum PermissionGuideButton: Equatable {
    case close
    case openSystemSettings
    case next
}

/// アクセシビリティの許可の案内の状態。
@Observable final class PermissionGuideModel {
    private let permission: AccessibilityPermissionChecking
    private let opener: AccessibilitySettingsOpening

    private(set) var isTrusted: Bool
    private(set) var reason: PermissionGuideReason = .launch
    private(set) var isPresented = false

    init(
        permission: AccessibilityPermissionChecking,
        opener: AccessibilitySettingsOpening = WorkspaceAccessibilitySettingsOpener()
    ) {
        self.permission = permission
        self.opener = opener
        self.isTrusted = permission.isTrusted
    }

    var state: PermissionGuideState {
        if isTrusted {
            return reason == .firstLaunch ? .readyForTutorial : .granted
        }
        return .notGranted(reason)
    }

    var allowsClosing: Bool {
        state != .readyForTutorial
    }

    var showsTutorialNote: Bool {
        state == .notGranted(.firstLaunch)
    }

    var buttons: [PermissionGuideButton] {
        switch state {
        case .granted: [.close]
        case .notGranted: [.close, .openSystemSettings]
        case .readyForTutorial: [.next]
        }
    }

    func refresh() {
        let trusted = permission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    func present(reason: PermissionGuideReason) {
        self.reason = reason
        refresh()
        isPresented = true
    }

    func presentOnLaunchIfNeeded() -> Bool {
        refresh()
        guard !isTrusted else { return false }
        present(reason: .launch)
        return true
    }

    func dismiss() {
        isPresented = false
    }

    func openSystemSettings() {
        if !permission.isTrusted {
            permission.requestSystemPrompt()
        }
        opener.openAccessibilitySettings()
    }
}
