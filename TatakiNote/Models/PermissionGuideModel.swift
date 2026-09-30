import Observation

/// @note p0-447
enum PermissionGuideReason: Equatable, Sendable {
    /// @note p0-448
    case launch
    /// @note p0-449
    case commitDenied
}

/// @note p0-450
enum PermissionGuideState: Equatable {
    case granted
    case notGranted(PermissionGuideReason)
}

/// @note p0-451
@Observable final class PermissionGuideModel {
    private let permission: AccessibilityPermissionChecking
    private let opener: AccessibilitySettingsOpening

    private(set) var isTrusted: Bool
    /// @note p0-452
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
        isTrusted ? .granted : .notGranted(reason)
    }

    /// @note p0-453
    func refresh() {
        let trusted = permission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// @note p0-454
    func present(reason: PermissionGuideReason) {
        self.reason = reason
        refresh()
        isPresented = true
    }

    /// @note p0-455
    func presentOnLaunchIfNeeded() -> Bool {
        refresh()
        guard !isTrusted else { return false }
        present(reason: .launch)
        return true
    }

    func dismiss() {
        isPresented = false
    }

    /// @note p0-456
    func openSystemSettings() {
        if !permission.isTrusted {
            permission.requestSystemPrompt()
        }
        opener.openAccessibilitySettings()
    }
}
