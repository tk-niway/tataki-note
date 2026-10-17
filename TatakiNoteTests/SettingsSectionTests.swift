import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct SettingsSectionTests {
    @Test("AC-1: サイドバーの項目は「一般」「ホットキーとキー操作」「パネル」「情報」の順で、表示名・アイコン・識別子に使う値が決まっていて、「エディタ設定」は無い")
    func sidebarSectionsInOrder() {
        #expect(SettingsSection.allCases == [.general, .keys, .panel, .appInfo])
        #expect(SettingsSection.allCases.map(\.displayName) == ["一般", "ホットキーとキー操作", "パネル", "情報"])
        #expect(SettingsSection.allCases.map(\.systemImage) == ["gearshape", "keyboard", "macwindow", "info.circle"])
        #expect(SettingsSection.allCases.map(\.rawValue) == ["general", "keys", "panel", "appInfo"])
        #expect(!SettingsSection.allCases.map(\.displayName).contains("エディタ設定"))
    }

    @Test("AC-4: 中身は 720×600 で、サイドバーの幅は 212、右側の中身の幅はウィンドウの幅からサイドバーと区切り線を引いた残りに固定される")
    func detailWidthFillsRemainder() {
        #expect(SettingsView.windowSize == CGSize(width: 720, height: 600))
        #expect(SettingsView.sidebarWidth == 212)
        #expect(SettingsView.detailWidth == 507)
        #expect(SettingsView.detailWidth == SettingsView.windowSize.width - SettingsView.sidebarWidth - SettingsView.dividerWidth)
        #expect(SettingsView.sidebarWidth + SettingsView.dividerWidth + SettingsView.detailWidth == SettingsView.windowSize.width)
        #expect(SettingsView.sidebarEdgeInset >= 12)
    }

    @Test("AC-9: 設定画面は「一般」を選んだ状態で始まり、「ホットキーとキー操作」「パネル」「情報」のどれを選んでいても開き直すと「一般」に戻る")
    func opensWithGeneral() {
        let model = SettingsWindowModel()
        #expect(model.selectedSection == .general)

        for section in [SettingsSection.keys, .panel, .appInfo] {
            model.selectedSection = section
            model.prepareForOpen()
            #expect(model.selectedSection == .general, "\(section)")
        }
    }

    @Test("AC-9: 「ホットキーとキー操作」「パネル」「情報」のどれを出したまま設定画面の窓を閉じても「一般」に戻る")
    func closingWindowReturnsToGeneral() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))

        let controller = SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil })
        )

        for section in [SettingsSection.keys, .panel, .appInfo] {
            controller.model.selectedSection = section

            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

            #expect(controller.model.selectedSection == .general, "\(section)")
        }
    }

    private func makeController(library: DraftLibrary, defaults: UserDefaults) -> SettingsWindowController {
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        return SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil }),
            library: library
        )
    }

    @Test("AC-18: 履歴の削除の確認中に設定画面の窓を閉じると、確認は閉じて履歴は残る")
    func closingWindowClosesHistoryConfirmation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let library = DraftLibrary(store: .inMemory)
        library.recordInsertion(text: "entry", appName: "Notes", bundleIdentifier: nil)
        let controller = makeController(library: library, defaults: defaults)

        controller.history.requestClear()
        #expect(controller.history.phase == .confirming)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(controller.history.phase == .idle)
        #expect(library.history.count == 1)
    }

    @Test("AC-18: 履歴を削除した後に設定画面の窓を閉じると、「削除しました」の段階は待ちに戻る")
    func closingWindowResetsClearedHistoryPhase() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let library = DraftLibrary(store: .inMemory)
        library.recordInsertion(text: "entry", appName: "Notes", bundleIdentifier: nil)
        let controller = makeController(library: library, defaults: defaults)

        controller.history.requestClear()
        controller.history.confirmClear()
        #expect(controller.history.phase == .cleared)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(controller.history.phase == .idle)
        #expect(controller.history.isClearAvailable == false)
    }

    @Test("AC-19: 設定画面の窓が閉じると、その場ではなく次の main の回で onDidClose が1回呼ばれる")
    func closingWindowCallsOnDidCloseOnNextTurn() async throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = makeController(library: DraftLibrary(store: .inMemory), defaults: defaults)
        var closeCount = 0
        controller.onDidClose = { closeCount += 1 }

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(closeCount == 0)
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { closeCount > 0 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(closeCount == 1)
    }

    @Test("AC-19: onDidClose が無くても、設定画面の窓を閉じて落ちない")
    func closingWindowWithoutOnDidCloseDoesNotCrash() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = makeController(library: DraftLibrary(store: .inMemory), defaults: defaults)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        #expect(controller.onDidClose == nil)
    }
}
