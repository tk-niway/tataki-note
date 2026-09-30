import ServiceManagement
import Testing
@testable import TatakiNote

/// @note p0-882
@MainActor
private final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus
    /// @note p0-883
    var statusAfterRegister: LoginItemStatus = .enabled
    var failsToRegister = false
    var failsToUnregister = false
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if failsToRegister {
            throw Failure()
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if failsToUnregister {
            throw Failure()
        }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCount += 1
    }
}

@MainActor
struct LaunchAtLoginModelTests {
    @Test("AC-7: 作った直後から Mac 側の状態を表示する。登録済み・承認待ちはオン、未登録・見つからないはオフで、承認待ちだけ承認を求める")
    func initialStatusFollowsMac() {
        let cases: [(LoginItemStatus, isEnabled: Bool, needsApproval: Bool)] = [
            (.notRegistered, false, false),
            (.enabled, true, false),
            (.requiresApproval, true, true),
            (.notFound, false, false),
        ]
        for (status, isEnabled, needsApproval) in cases {
            let service = FakeLoginItemService(status: status)
            let model = LaunchAtLoginModel(service: service)
            #expect(model.status == status, "\(status)")
            #expect(model.isEnabled == isEnabled, "\(status)")
            #expect(model.needsApproval == needsApproval, "\(status)")
            #expect(model.lastError == nil, "\(status)")
            // @note p0-884
            #expect(service.registerCount == 0, "\(status)")
            #expect(service.unregisterCount == 0, "\(status)")
        }
    }

    @Test("AC-7: オンにすると登録を頼んでオンになり、オフにすると登録を外してオフになる")
    func enableAndDisable() {
        let service = FakeLoginItemService(status: .notRegistered)
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 0)
        #expect(model.status == .enabled)
        #expect(model.isEnabled == true)
        #expect(model.needsApproval == false)
        #expect(model.lastError == nil)

        model.setEnabled(false)
        #expect(service.registerCount == 1)
        #expect(service.unregisterCount == 1)
        #expect(model.status == .notRegistered)
        #expect(model.isEnabled == false)
        #expect(model.lastError == nil)
    }

    @Test("AC-7: 登録して Mac が承認を求めたときは、オンのまま承認を求め、「システム設定を開く」でログイン項目の設定を開く")
    func registerRequiringApproval() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)
        #expect(model.status == .requiresApproval)
        #expect(model.isEnabled == true)
        #expect(model.needsApproval == true)
        #expect(model.lastError == nil)

        model.openSystemSettings()
        #expect(service.openSystemSettingsCount == 1)

        // @note p0-885
        model.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(model.isEnabled == false)
        #expect(model.needsApproval == false)
    }

    @Test("AC-7: 登録に失敗すると失敗を知らせ、Mac 側の状態のまま(オフ)表示する。次に成功すると知らせが消える")
    func registerFailure() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.failsToRegister = true
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(true)
        #expect(service.registerCount == 1)
        #expect(model.lastError == .registerFailed)
        #expect(model.status == .notRegistered)
        #expect(model.isEnabled == false)

        // @note p0-886
        model.refresh()
        #expect(model.lastError == .registerFailed)

        service.failsToRegister = false
        model.setEnabled(true)
        #expect(service.registerCount == 2)
        #expect(model.lastError == nil)
        #expect(model.isEnabled == true)
    }

    @Test("AC-7: 外すのに失敗すると失敗を知らせ、Mac 側の状態のまま(オン)表示する。Mac 側で外されれば読み直してオフになる")
    func unregisterFailure() {
        let service = FakeLoginItemService(status: .enabled)
        service.failsToUnregister = true
        let model = LaunchAtLoginModel(service: service)

        model.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(model.lastError == .unregisterFailed)
        #expect(model.status == .enabled)
        #expect(model.isEnabled == true)

        // @note p0-887
        service.status = .notRegistered
        model.refresh()
        #expect(model.isEnabled == false)
        #expect(model.lastError == .unregisterFailed)
    }

    @Test("AC-7: 読み直すと Mac 側で変わった状態になる(読み直すまでは前の状態のまま)")
    func refreshFollowsMacChanges() {
        let service = FakeLoginItemService(status: .enabled)
        let model = LaunchAtLoginModel(service: service)
        #expect(model.isEnabled == true)

        // @note p0-888
        service.status = .notRegistered
        #expect(model.isEnabled == true)
        model.refresh()
        #expect(model.status == .notRegistered)
        #expect(model.isEnabled == false)

        // @note p0-889
        service.status = .requiresApproval
        model.refresh()
        #expect(model.needsApproval == true)
        #expect(model.isEnabled == true)
        service.status = .notFound
        model.refresh()
        #expect(model.status == .notFound)
        #expect(model.isEnabled == false)
        #expect(model.needsApproval == false)
        // @note p0-890
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test("AC-7: Mac 側の状態(SMAppService.Status)を、同じ意味の LoginItemStatus に写す")
    func statusFromServiceManagement() {
        #expect(LoginItemStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test("AC-7: UI テスト用のログイン項目は、未登録から始まり、登録で有効・外すで未登録になる(OS には何もしない)")
    func inMemoryService() throws {
        let service = InMemoryLoginItemService()
        #expect(service.status == .notRegistered)
        try service.register()
        #expect(service.status == .enabled)
        try service.unregister()
        #expect(service.status == .notRegistered)
        // @note p0-891
        service.openSystemSettingsLoginItems()

        let model = LaunchAtLoginModel(service: InMemoryLoginItemService())
        model.setEnabled(true)
        #expect(model.isEnabled == true)
        model.setEnabled(false)
        #expect(model.isEnabled == false)
        #expect(model.lastError == nil)
    }
}
