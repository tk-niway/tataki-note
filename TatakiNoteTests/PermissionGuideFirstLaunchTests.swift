import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PermissionGuideFirstLaunchTests {
    private func makeModel(isTrusted: Bool) -> (PermissionGuideModel, PermissionStub) {
        let permission = PermissionStub(isTrusted: isTrusted)
        return (PermissionGuideModel(permission: permission, opener: SettingsOpenerStub()), permission)
    }

    private func makeController(model: PermissionGuideModel) throws -> (PermissionGuideWindowController, () -> Void) {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let controller = PermissionGuideWindowController(model: model, settings: settings)
        return (controller, { defaults.removePersistentDomain(forName: name) })
    }

    private func isCloseButtonVisible(in window: NSWindow) -> Bool {
        guard let button = window.standardWindowButton(.closeButton) else { return false }
        return !button.isHidden
    }

    @Test("AC-5: 初回起動の案内で許可が無い間は、「閉じる」「システム設定を開く」と注記が出て、閉じられる")
    func firstLaunchWithoutPermissionShowsNoteAndCanClose() throws {
        let (model, _) = makeModel(isTrusted: false)
        model.present(reason: .firstLaunch)

        #expect(model.state == .notGranted(.firstLaunch))
        #expect(model.buttons == [.close, .openSystemSettings])
        #expect(model.showsTutorialNote == true)
        #expect(model.allowsClosing == true)

        let (controller, cleanup) = try makeController(model: model)
        defer { cleanup() }
        let window = controller.makeWindow()
        controller.updateClosability(of: window)

        #expect(window.styleMask.contains(.closable))
        #expect(isCloseButtonVisible(in: window))
        #expect(controller.windowShouldClose(window) == true)
    }

    @Test("AC-5: 初回起動の案内を閉じても、チュートリアルを開く処理は呼ばれない")
    func closingFirstLaunchGuideDoesNotOpenTutorial() throws {
        let (model, _) = makeModel(isTrusted: false)
        let (controller, cleanup) = try makeController(model: model)
        defer { cleanup() }
        var proceedCount = 0
        controller.onProceedToTutorial = { proceedCount += 1 }

        controller.show(reason: .firstLaunch)
        #expect(model.isPresented == true)
        controller.close()

        #expect(model.isPresented == false)
        #expect(proceedCount == 0)
    }

    @Test("AC-6: 初回起動の案内を開いている間に許可されると、ボタンは「次へ」だけになり、× が消えて閉じられない")
    func grantedDuringFirstLaunchShowsNextOnly() throws {
        let (model, permission) = makeModel(isTrusted: false)
        model.present(reason: .firstLaunch)
        let (controller, cleanup) = try makeController(model: model)
        defer { cleanup() }
        let window = controller.makeWindow()
        controller.updateClosability(of: window)
        #expect(window.styleMask.contains(.closable))
        #expect(isCloseButtonVisible(in: window))

        permission.isTrusted = true
        model.refresh()
        controller.updateClosability(of: window)

        #expect(model.state == .readyForTutorial)
        #expect(model.buttons == [.next])
        #expect(model.allowsClosing == false)
        #expect(model.showsTutorialNote == false)
        #expect(window.styleMask.contains(.closable) == false)
        #expect(isCloseButtonVisible(in: window) == false)
        #expect(controller.windowShouldClose(window) == false)
    }

    @Test("AC-6: 窓の styleMask は、閉じてよいときだけ .closable を含む")
    func styleMaskFollowsClosability() {
        #expect(PermissionGuideWindowController.styleMask(allowsClosing: true) == [.titled, .closable])
        #expect(PermissionGuideWindowController.styleMask(allowsClosing: false) == [.titled])
    }

    @Test("AC-7: 「次へ」を押すと、許可の案内が閉じてチュートリアルを開く処理が1回呼ばれる")
    func proceedClosesGuideAndOpensTutorial() throws {
        let (model, _) = makeModel(isTrusted: true)
        let (controller, cleanup) = try makeController(model: model)
        defer {
            controller.close()
            cleanup()
        }
        var proceedCount = 0
        controller.onProceedToTutorial = { proceedCount += 1 }

        controller.show(reason: .firstLaunch)
        #expect(model.state == .readyForTutorial)
        #expect(model.isPresented == true)

        controller.proceedToTutorial()

        #expect(proceedCount == 1)
        #expect(model.isPresented == false)
    }

    @Test("AC-8: 「次へ」を出している間に許可が外れると、許可される前の表示に戻る")
    func revokedWhileReadyReturnsToNotGranted() throws {
        let (model, permission) = makeModel(isTrusted: true)
        model.present(reason: .firstLaunch)
        let (controller, cleanup) = try makeController(model: model)
        defer { cleanup() }
        let window = controller.makeWindow()
        controller.updateClosability(of: window)
        #expect(model.buttons == [.next])
        #expect(window.styleMask.contains(.closable) == false)
        #expect(isCloseButtonVisible(in: window) == false)

        permission.isTrusted = false
        model.refresh()
        controller.updateClosability(of: window)

        #expect(model.state == .notGranted(.firstLaunch))
        #expect(model.buttons == [.close, .openSystemSettings])
        #expect(model.showsTutorialNote == true)
        #expect(model.allowsClosing == true)
        #expect(window.styleMask.contains(.closable))
        #expect(isCloseButtonVisible(in: window))
        #expect(controller.windowShouldClose(window) == true)
    }

    @Test("AC-9: 起動時の案内と確定時の案内は、許可されても「次へ」にならず、注記も出ず、閉じられる")
    func otherReasonsNeverBecomeTutorialPrompt() throws {
        for reason in [PermissionGuideReason.launch, .commitDenied] {
            let (model, permission) = makeModel(isTrusted: false)
            model.present(reason: reason)

            #expect(model.state == .notGranted(reason))
            #expect(model.buttons == [.close, .openSystemSettings])
            #expect(model.showsTutorialNote == false)
            #expect(model.allowsClosing == true)

            permission.isTrusted = true
            model.refresh()

            #expect(model.state == .granted)
            #expect(model.buttons == [.close])
            #expect(model.showsTutorialNote == false)
            #expect(model.allowsClosing == true)

            let (controller, cleanup) = try makeController(model: model)
            defer { cleanup() }
            let window = controller.makeWindow()
            controller.updateClosability(of: window)
            #expect(window.styleMask.contains(.closable))
            #expect(isCloseButtonVisible(in: window))
            #expect(controller.windowShouldClose(window) == true)
        }
    }
}
