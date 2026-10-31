import Observation
import ServiceManagement

/// ログイン項目の登録の状態(`SMAppService.Status` から作る)。
enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

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

/// ログイン項目の登録(OS の呼び出し)。
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// 本物のログイン項目(`SMAppService.mainApp`)。
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

/// OS に何もしないログイン項目(UI テストで使う)。
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

    func openSystemSettingsLoginItems() {}
}

/// ログイン項目の登録・解除の失敗。
enum LaunchAtLoginError: Equatable, Sendable {
    case registerFailed
    case unregisterFailed
}

/// 設定画面の「ログイン時に起動」の状態。
@Observable final class LaunchAtLoginModel {
    private let service: LoginItemService

    private(set) var status: LoginItemStatus
    private(set) var lastError: LaunchAtLoginError?

    init(service: LoginItemService) {
        self.service = service
        self.status = service.status
        self.lastError = nil
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        let current = service.status
        if current != status {
            status = current
        }
    }

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
