import Observation
import ServiceManagement

/// @note p0-268
enum LoginItemStatus: Equatable, Sendable {
    /// @note p0-269
    case notRegistered
    /// @note p0-270
    case enabled
    /// @note p0-271
    case requiresApproval
    /// @note p0-272
    case notFound

    /// @note p0-273
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notRegistered
        }
    }
}

/// @note p0-274
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// @note p0-275
    func openSystemSettingsLoginItems()
}

/// @note p0-276
struct MainAppLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// @note p0-277
final class InMemoryLoginItemService: LoginItemService {
    private(set) var status: LoginItemStatus

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }

    /// @note p0-278
    func openSystemSettingsLoginItems() {}
}

/// @note p0-279
enum LaunchAtLoginError: Equatable, Sendable {
    case registerFailed
    case unregisterFailed
}

/// @note p0-280
@Observable final class LaunchAtLoginModel {
    private let service: LoginItemService

    private(set) var status: LoginItemStatus
    /// @note p0-281
    private(set) var lastError: LaunchAtLoginError?

    /// @note p0-282
    init(service: LoginItemService) {
        self.service = service
        self.status = service.status
        self.lastError = nil
    }

    /// @note p0-283
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    /// @note p0-284
    func refresh() {
        let current = service.status
        if current != status {
            status = current
        }
    }

    /// @note p0-285
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = enabled ? .registerFailed : .unregisterFailed
        }
        refresh()
    }

    func openSystemSettings() {
        service.openSystemSettingsLoginItems()
    }
}
