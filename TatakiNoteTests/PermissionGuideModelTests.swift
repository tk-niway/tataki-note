import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class GuidePermissionStub: AccessibilityPermissionChecking {
    var isTrusted: Bool
    private(set) var promptCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func requestSystemPrompt() {
        promptCount += 1
    }
}

@MainActor
final class SettingsOpenerStub: AccessibilitySettingsOpening {
    private(set) var openCount = 0

    func openAccessibilitySettings() {
        openCount += 1
    }
}

@MainActor
struct PermissionGuideModelTests {
    @Test("AC-1: 許可が無いと、起動時の案内が開き、許可が無いこと(手順を出す状態)になる")
    func launchWithoutPermissionPresents() {
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: SettingsOpenerStub())

        #expect(model.presentOnLaunchIfNeeded() == true)
        #expect(model.isPresented == true)
        #expect(model.state == .notGranted(.launch))
    }

    @Test("AC-2: 許可があると、起動時の案内は開かない")
    func launchWithPermissionDoesNotPresent() {
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: true), opener: SettingsOpenerStub())

        #expect(model.presentOnLaunchIfNeeded() == false)
        #expect(model.isPresented == false)
        #expect(model.state == .granted)
    }

    @Test("AC-1, AC-2: 起動時の判定は、作った後に変わった許可の状態で行う")
    func launchUsesCurrentPermission() {
        let permission = GuidePermissionStub(isTrusted: true)
        let model = PermissionGuideModel(permission: permission, opener: SettingsOpenerStub())
        permission.isTrusted = false

        #expect(model.presentOnLaunchIfNeeded() == true)
        #expect(model.state == .notGranted(.launch))
    }

    @Test("AC-3: 確定で開くと、下書きに残っていることを出す理由になる")
    func commitDeniedPresents() {
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: SettingsOpenerStub())

        model.present(reason: .commitDenied)

        #expect(model.isPresented == true)
        #expect(model.state == .notGranted(.commitDenied))
    }

    @Test("AC-4: 開くと、許可があれば許可があること、無ければ手順を出す状態になる")
    func presentShowsCurrentState() {
        let granted = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: true), opener: SettingsOpenerStub())
        granted.present(reason: .launch)
        #expect(granted.isPresented == true)
        #expect(granted.state == .granted)

        let notGranted = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: SettingsOpenerStub())
        notGranted.present(reason: .launch)
        #expect(notGranted.isPresented == true)
        #expect(notGranted.state == .notGranted(.launch))
    }

    @Test("AC-5: 「システム設定を開く」でシステム設定のアクセシビリティを開く操作が1回呼ばれ、開く URL は決めたもの")
    func openSystemSettingsCallsOpener() throws {
        let opener = SettingsOpenerStub()
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: opener)
        model.present(reason: .launch)

        model.openSystemSettings()

        #expect(opener.openCount == 1)
        #expect(
            WorkspaceAccessibilitySettingsOpener.settingsURLString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        let url = try #require(URL(string: WorkspaceAccessibilitySettingsOpener.settingsURLString))
        #expect(url.scheme == "x-apple.systempreferences")
    }

    @Test("「システム設定を開く」は、許可が無ければシステムの許可のダイアログを求めてから開く(一覧に載るように)")
    func openSystemSettingsRequestsPromptWhenNotTrusted() {
        let permission = GuidePermissionStub(isTrusted: false)
        let opener = SettingsOpenerStub()
        let model = PermissionGuideModel(permission: permission, opener: opener)

        model.openSystemSettings()

        #expect(permission.promptCount == 1)
        #expect(opener.openCount == 1)
    }

    @Test("「システム設定を開く」は、許可があればシステムの許可のダイアログを求めない")
    func openSystemSettingsSkipsPromptWhenTrusted() {
        let permission = GuidePermissionStub(isTrusted: true)
        let opener = SettingsOpenerStub()
        let model = PermissionGuideModel(permission: permission, opener: opener)

        model.openSystemSettings()

        #expect(permission.promptCount == 0)
        #expect(opener.openCount == 1)
    }

    @Test("AC-6: 開いている間に許可が変わると、確かめ直すだけで表示の状態が変わる")
    func refreshFollowsPermissionChanges() {
        let permission = GuidePermissionStub(isTrusted: false)
        let model = PermissionGuideModel(permission: permission, opener: SettingsOpenerStub())
        model.present(reason: .commitDenied)
        #expect(model.state == .notGranted(.commitDenied))

        permission.isTrusted = true
        model.refresh()
        #expect(model.state == .granted)
        #expect(model.isPresented == true)

        permission.isTrusted = false
        model.refresh()
        #expect(model.state == .notGranted(.commitDenied))
    }

    @Test("閉じると開いていない状態になる")
    func dismissClears() {
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: SettingsOpenerStub())
        model.present(reason: .launch)

        model.dismiss()

        #expect(model.isPresented == false)
    }

    @Test("AC-13: 起動時の案内を開いたまま確定で開き直すと、理由が確定に変わり、下書きの表示の状態になる")
    func representReplacesReason() {
        let model = PermissionGuideModel(permission: GuidePermissionStub(isTrusted: false), opener: SettingsOpenerStub())
        model.present(reason: .launch)

        model.present(reason: .commitDenied)

        #expect(model.reason == .commitDenied)
        #expect(model.state == .notGranted(.commitDenied))
        #expect(model.isPresented == true)

        model.present(reason: .commitDenied)
        #expect(model.state == .notGranted(.commitDenied))
        #expect(model.isPresented == true)
    }
}
