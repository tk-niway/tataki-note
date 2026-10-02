import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppInfoTutorialTests {
    private func makeModel(onOpenTutorial: @escaping () -> Void) -> AppInfoModel {
        AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true)),
            onOpenTutorial: onOpenTutorial
        )
    }

    @Test("AC-20: openTutorial() でチュートリアルを開く処理が押した回数だけ呼ばれる")
    func openTutorialCallsHandler() {
        var openCount = 0
        let model = makeModel { openCount += 1 }
        #expect(openCount == 0)

        model.openTutorial()
        #expect(openCount == 1)

        model.openTutorial()
        #expect(openCount == 2)
    }

    @Test("AC-20: 開く処理を渡さなくても openTutorial() は何も起こさず呼べる")
    func openTutorialWithoutHandlerIsHarmless() {
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
        )
        model.openTutorial()
        #expect(model.permissionStatus.isTrusted)
    }
}
