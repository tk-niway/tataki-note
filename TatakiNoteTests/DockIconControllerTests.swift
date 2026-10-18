import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class PolicyRecorder {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var hideCount = 0

    func record(_ policy: NSApplication.ActivationPolicy) {
        policies.append(policy)
    }

    func recordHide() {
        hideCount += 1
    }
}

@MainActor
struct DockIconControllerTests {
    private func withController(
        showsDockIcon: Bool,
        _ body: (DockIconController, AppSettings, PolicyRecorder) async throws -> Void
    ) async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.showsDockIcon = showsDockIcon
        let recorder = PolicyRecorder()
        let controller = DockIconController(
            settings: settings,
            setActivationPolicy: { recorder.record($0) },
            didHideIcon: { recorder.recordHide() }
        )
        try await body(controller, settings, recorder)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("AC-4: 設定の値に合うアクティベーションポリシーは、オンなら regular、オフなら accessory")
    func policyFollowsSetting() {
        #expect(DockIconController.activationPolicy(showsDockIcon: true) == .regular)
        #expect(DockIconController.activationPolicy(showsDockIcon: false) == .accessory)
    }

    @Test("AC-4: 見張りを始めたときに今の設定を当てる(オンなら regular、オフなら accessory)。始めただけでは設定ウィンドウを前に出し直さない", arguments: [true, false])
    func startAppliesCurrentSetting(showsDockIcon: Bool) async throws {
        try await withController(showsDockIcon: showsDockIcon) { controller, _, recorder in
            controller.start()
            try await settle()

            #expect(recorder.policies == [DockIconController.activationPolicy(showsDockIcon: showsDockIcon)])
            #expect(recorder.hideCount == 0)
        }
    }

    @Test("AC-4: 設定を変えるたびに、起動し直さずに当て直す")
    func changingSettingReappliesPolicy() async throws {
        try await withController(showsDockIcon: true) { controller, settings, recorder in
            controller.start()

            settings.showsDockIcon = false
            await yieldUntil { recorder.policies.count == 2 }
            settings.showsDockIcon = true
            await yieldUntil { recorder.policies.count == 3 }
            settings.showsDockIcon = false
            await yieldUntil { recorder.policies.count == 4 }

            #expect(recorder.policies == [.regular, .accessory, .regular, .accessory])
        }
    }

    @Test("AC-4: オフに切り替えたときだけ、設定ウィンドウを前に出し直す処理を呼ぶ")
    func hidingIconBringsSettingsToFront() async throws {
        try await withController(showsDockIcon: true) { controller, settings, recorder in
            controller.start()

            settings.showsDockIcon = false
            await yieldUntil { recorder.hideCount == 1 }
            settings.showsDockIcon = true
            await yieldUntil { recorder.policies.count == 3 }
            try await settle()

            #expect(recorder.hideCount == 1)

            settings.showsDockIcon = false
            await yieldUntil { recorder.hideCount == 2 }

            #expect(recorder.hideCount == 2)
        }
    }

    @Test("AC-4: 同じ値を書いても当て直さない")
    func sameValueDoesNotReapply() async throws {
        try await withController(showsDockIcon: true) { controller, settings, recorder in
            controller.start()
            settings.showsDockIcon = true
            try await settle()

            #expect(recorder.policies == [.regular])

            settings.showsDockIcon = false
            await yieldUntil { recorder.policies.count == 2 }
            settings.showsDockIcon = false
            try await settle()

            #expect(recorder.policies == [.regular, .accessory])
            #expect(recorder.hideCount == 1)
        }
    }

    @Test("AC-4: 「メニューバーにアイコンを表示」を変えても当て直さない")
    func menuBarIconSettingDoesNotReapply() async throws {
        try await withController(showsDockIcon: true) { controller, settings, recorder in
            controller.start()

            settings.hidesMenuBarIcon = true
            try await settle()
            settings.hidesMenuBarIcon = false
            try await settle()

            #expect(recorder.policies == [.regular])
            #expect(recorder.hideCount == 0)
        }
    }

    @Test("AC-4: 見張りを2回始めても、最初の適用は1回だけ")
    func startingTwiceAppliesOnce() async throws {
        try await withController(showsDockIcon: true) { controller, settings, recorder in
            controller.start()
            controller.start()

            settings.showsDockIcon = false
            await yieldUntil { recorder.policies.count == 2 }
            try await settle()

            #expect(recorder.policies == [.regular, .accessory])
        }
    }
}
