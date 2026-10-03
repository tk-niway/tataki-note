import AppKit
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

    @Test("openTutorial() でチュートリアルを開く処理が押した回数だけ呼ばれる")
    func openTutorialCallsHandler() {
        var openCount = 0
        let model = makeModel { openCount += 1 }
        #expect(openCount == 0)

        model.openTutorial()
        #expect(openCount == 1)

        model.openTutorial()
        #expect(openCount == 2)
    }

    @Test("開く処理を渡さなくても openTutorial() は何も起こさず呼べる")
    func openTutorialWithoutHandlerIsHarmless() {
        let model = AppInfoModel(
            infoDictionary: [:],
            permissionStatus: PermissionGuideModel(permission: OverriddenAccessibilityPermission(isTrusted: true))
        )
        model.openTutorial()
        #expect(model.permissionStatus.isTrusted)
    }

    private func withTutorialModel(
        hotkey: PanelShortcut?,
        _ body: (TutorialModel) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let model = TutorialModel(ownProcessIdentifier: 4242, settings: settings, hotkey: { hotkey })
        try body(model)
    }

    @Test("AC-25: 窓の冒頭の文は、練習用のチャットで送るまでをたどる形で、「練習用の入力欄」とは言わない")
    func introductionPointsToPracticeChat() {
        let text = TutorialModel.introduction

        #expect(text.contains("練習用のチャット"))
        #expect(text.contains("送る"))
        #expect(!text.contains("練習用の入力欄"))
    }

    @Test("AC-25: 設定の「アプリ情報」の説明文は、練習用のチャットで書いて送るまでをたどる形")
    func tutorialDescriptionPointsToPracticeChat() {
        let text = AppInfoModel.tutorialDescription

        #expect(text.contains("練習用のチャット"))
        #expect(text.contains("送る"))
        #expect(!text.contains("練習用の入力欄"))
    }

    @Test("AC-25: 手順1の案内(ホットキーがあるとき)は、練習用のチャットの入力欄を示す")
    func openPanelInstructionPointsToPracticeChatInput() throws {
        let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        try withTutorialModel(hotkey: hotkey) { model in
            let text = model.openPanelInstruction

            #expect(text.contains("練習用のチャットの入力欄"))
            #expect(!text.contains("練習用の入力欄"))
            #expect(text.contains(hotkey.displayText))
        }
    }
}
