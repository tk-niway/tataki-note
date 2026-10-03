import AppKit
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct AppWindowTests {
    private func windowIdentifiers(_ identifier: String) -> Set<ObjectIdentifier> {
        Set(NSApp.windows.filter { $0.identifier?.rawValue == identifier }.map { ObjectIdentifier($0) })
    }

    private func openTwice(identifier: String, show: () -> Void) throws -> NSWindow {
        let beforeFirst = windowIdentifiers(identifier)
        show()
        let afterFirst = windowIdentifiers(identifier)
        let created = afterFirst.subtracting(beforeFirst)
        #expect(created.count == 1)
        let window = try #require(NSApp.windows.first { created.contains(ObjectIdentifier($0)) })

        show()
        #expect(windowIdentifiers(identifier).subtracting(afterFirst).isEmpty)
        #expect(window.isVisible)
        return window
    }

    private func contentSize(of window: NSWindow) -> NSSize {
        window.contentRect(forFrameRect: window.frame).size
    }

    private func expectContentSize(_ window: NSWindow, _ expected: NSSize) {
        let size = contentSize(of: window)
        let visible = window.screen?.visibleFrame.size ?? .zero
        #expect(size.width == expected.width || window.frame.width >= visible.width)
        #expect(size.height == expected.height || window.frame.height >= visible.height)
    }

    private func isCloseButtonVisible(in window: NSWindow) -> Bool {
        guard let button = window.standardWindowButton(.closeButton) else { return false }
        return !button.isHidden
    }

    private func makeSettingsController(settings: AppSettings) -> SettingsWindowController {
        SettingsWindowController(
            settings: settings,
            launchAtLogin: LaunchAtLoginModel(service: InMemoryLoginItemService()),
            appInfo: AppInfoModel(
                infoDictionary: [:],
                permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
            ),
            panelDefaultSize: PanelDefaultSizeModel(settings: settings, currentPanelSize: { nil })
        )
    }

    private func makeTutorialController(settings: AppSettings) -> TutorialWindowController {
        TutorialWindowController(settings: settings, panelModel: PanelModel(), focusWindow: { _ in })
    }

    // MARK: - AC-10 許可の状態の確かめ方

    @Test("AC-10: 許可の状態を変えると、確かめ直しで案内のモデルの状態が追いつき、そのたびに onRefresh が呼ばれ、取り消すと変わらない")
    func watchFollowsPermissionUntilCancelled() async throws {
        let permission = PermissionStub(isTrusted: false)
        let model = PermissionGuideModel(permission: permission, opener: SettingsOpenerStub())
        var refreshCount = 0

        let watching = Task { await model.watch(interval: .milliseconds(10), onRefresh: { refreshCount += 1 }) }

        permission.isTrusted = true
        #expect(try await waitUntil(attempts: 200, interval: .milliseconds(10)) { model.isTrusted })
        #expect(refreshCount > 0)
        permission.isTrusted = false
        #expect(try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !model.isTrusted })

        watching.cancel()
        await watching.value

        let countAfterCancel = refreshCount
        permission.isTrusted = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(!model.isTrusted)
        #expect(refreshCount == countAfterCancel)
    }

    @Test("AC-10: 許可の案内を開いている間に許可が変わると数秒のうちに状態が変わり、閉じた後は変わらない")
    func permissionGuideWindowFollowsPermissionUntilClosed() async throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let permission = PermissionStub(isTrusted: false)
        let model = PermissionGuideModel(permission: permission, opener: SettingsOpenerStub())
        let controller = PermissionGuideWindowController(model: model, settings: temp.makeSettings())
        defer { controller.close() }

        controller.show(reason: .launch)
        #expect(!model.isTrusted)

        permission.isTrusted = true
        #expect(try await waitUntil(attempts: 60, interval: .milliseconds(50)) { model.isTrusted })

        controller.close()
        permission.isTrusted = false
        try await Task.sleep(for: .milliseconds(1_300))
        #expect(model.isTrusted)
    }

    // MARK: - AC-11 窓を出す処理

    @Test("AC-11: AppWindow.prepare は窓が無いときだけ作って大きさを決め、あるときはそのまま返す")
    func prepareMakesOnlyWhenMissing() throws {
        let delegate = WindowDelegateStub()
        var makeCount = 0
        let make = {
            makeCount += 1
            return AppWindow.make(
                title: "題名",
                identifier: "appWindowTest",
                styleMask: [.titled, .closable],
                delegate: delegate,
                rootView: Text("本文")
            )
        }

        let first = AppWindow.prepare(existing: nil, make: make, initialContentSize: { _ in NSSize(width: 300, height: 200) })
        let second = AppWindow.prepare(existing: first, make: make, initialContentSize: { _ in NSSize(width: 100, height: 100) })

        #expect(first === second)
        #expect(makeCount == 1)
        #expect(contentSize(of: first) == NSSize(width: 300, height: 200))
        #expect(first.title == "題名")
        #expect(first.identifier?.rawValue == "appWindowTest")
        #expect(first.isReleasedWhenClosed == false)
        #expect(first.delegate === delegate)
        #expect(first.contentView is NSHostingView<Text>)
        #expect(first.isVisible == false)
    }

    @Test("AC-11: チュートリアルの窓は何度開いても同じ1枚で、開くと見え、大きさ・題名・識別子・閉じるボタンが決まった形になる")
    func tutorialWindowOpensOnce() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let controller = makeTutorialController(settings: temp.makeSettings())
        defer { controller.close() }

        controller.show()
        let first = try #require(controller.window)
        controller.show()
        let second = try #require(controller.window)

        #expect(first === second)
        #expect(first.isVisible)
        expectContentSize(first, TutorialWindowController.contentSize)
        #expect(first.title == "TatakiNote の使い方")
        #expect(first.identifier?.rawValue == "tutorial")
        #expect(first.styleMask == [.titled, .closable])
        #expect(isCloseButtonVisible(in: first))
    }

    @Test("AC-11: 設定の窓は何度開いても1枚で、開くと見え、大きさ・題名・識別子・閉じるボタンが決まった形になる")
    func settingsWindowOpensOnce() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let controller = makeSettingsController(settings: temp.makeSettings())

        let window = try openTwice(identifier: "settings", show: controller.show)
        defer { window.close() }

        expectContentSize(window, SettingsView.windowSize)
        #expect(window.title == "TatakiNote の設定")
        #expect(window.styleMask == [.titled, .closable, .fullSizeContentView])
        #expect(isCloseButtonVisible(in: window))
    }

    @Test("AC-11: 許可の案内の窓は何度開いても1枚で、開くと見え、大きさ・題名・識別子・閉じるボタンが決まった形になる")
    func permissionGuideWindowOpensOnce() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let model = PermissionGuideModel(permission: PermissionStub(isTrusted: false), opener: SettingsOpenerStub())
        let controller = PermissionGuideWindowController(model: model, settings: temp.makeSettings())
        defer { controller.close() }
        let probe = controller.makeWindow()
        let fittingSize = try #require(probe.contentView?.fittingSize)

        let window = try openTwice(identifier: "permissionGuide") { controller.show(reason: .launch) }
        #expect(window !== probe)

        let size = contentSize(of: window)
        #expect(abs(size.width - fittingSize.width) < 1)
        #expect(abs(size.height - fittingSize.height) < 1)
        #expect(window.title == "アクセシビリティの許可")
        #expect(window.styleMask == [.titled, .closable])
        #expect(isCloseButtonVisible(in: window))
    }

    @Test("AC-11: 許可の案内の窓は、閉じてはいけない状態で開くと閉じるボタンが無い")
    func permissionGuideWindowHidesCloseButtonWhenClosingIsNotAllowed() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let model = PermissionGuideModel(permission: PermissionStub(isTrusted: true), opener: SettingsOpenerStub())
        let controller = PermissionGuideWindowController(model: model, settings: temp.makeSettings())
        defer {
            model.dismiss()
            controller.close()
        }

        let window = try openTwice(identifier: "permissionGuide") { controller.show(reason: .firstLaunch) }

        #expect(model.allowsClosing == false)
        #expect(window.styleMask == [.titled])
        #expect(isCloseButtonVisible(in: window) == false)
    }

    // MARK: - AC-12 テーマ

    @Test("AC-12: テーマを変えると、開き直さずにチュートリアルの窓の外観がそのテーマになり、「システム」なら外観の指定が外れる")
    func tutorialWindowFollowsTheme() async throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        settings.theme = .light
        let controller = makeTutorialController(settings: settings)
        defer { controller.close() }

        controller.show()
        let window = try #require(controller.window)
        func settle(_ condition: () -> Bool) async throws {
            try await waitUntil(
                attempts: 40,
                interval: .milliseconds(50),
                beforeEachCheck: { window.contentView?.layoutSubtreeIfNeeded() },
                condition
            )
        }

        try await settle { window.appearance?.name == .aqua }
        #expect(window.appearance?.name == .aqua)

        settings.theme = .dark
        try await settle { window.appearance?.name == .darkAqua }
        #expect(window.appearance?.name == .darkAqua)

        settings.theme = .system
        try await settle { window.appearance == nil }
        #expect(window.appearance == nil)
    }
}

private final class WindowDelegateStub: NSObject, NSWindowDelegate {}
