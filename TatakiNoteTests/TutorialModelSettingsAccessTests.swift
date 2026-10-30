import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialModelSettingsAccessTests {
    private static let ownPid: pid_t = 4242
    private let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

    private func withModel(
        hasHotkey: Bool,
        _ body: (TutorialModel, AppSettings) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let shortcut: PanelShortcut? = hasHotkey ? hotkey : nil
        let model = TutorialModel(ownProcessIdentifier: Self.ownPid, settings: settings, hotkey: { shortcut })
        try body(model, settings)
    }

    private func iconCount(_ parts: [TutorialTextPart]) -> Int {
        parts.filter { $0 == .menuBarIcon }.count
    }

    private func textBeforeIcon(_ parts: [TutorialTextPart]) -> String? {
        guard let index = parts.firstIndex(of: .menuBarIcon), index > 0,
              case .text(let string) = parts[index - 1] else { return nil }
        return string
    }

    @Test("AC-1: 手順4の紹介は「ホットキーの変更」「書きかけ」「設定の開き方」の3つがこの順に並び、既存の2つは変わらない")
    func introductionsInOrder() {
        #expect(TutorialNextStepIntroduction.allCases == [.hotkeyChange, .draftKept, .settingsAccess])
        #expect(TutorialNextStepIntroduction.settingsAccess.heading == "設定の開き方")
        #expect(TutorialNextStepIntroduction.hotkeyChange.heading == "ホットキーの変更")
        #expect(TutorialNextStepIntroduction.hotkeyChange.text == "設定の「ホットキーとキー操作」の「パネルを開く・閉じる」で変えられます。")
        #expect(TutorialNextStepIntroduction.draftKept.heading == "書きかけ")
        #expect(TutorialNextStepIntroduction.draftKept.text == "esc でパネルを閉じても、書いた文章はパネルに残ります。次に開くと続きから書けます。")
    }

    @Test("AC-2: 「設定の開き方」の紹介は、アイコンから「設定」を選ぶことと ⌘, を伝え、「アイコン」の直後にアイコンの部品を1つ含む")
    func settingsAccessIntroduction() {
        let parts = TutorialNextStepIntroduction.settingsAccess.parts
        let text = TutorialNextStepIntroduction.settingsAccess.text

        #expect(iconCount(parts) == 1)
        #expect(textBeforeIcon(parts)?.hasSuffix("アイコン") == true)
        #expect(text.contains("メニューバーの TatakiNote のアイコン"))
        #expect(text.contains("「設定」を選ぶ"))
        #expect(text.contains("⌘,"))
        #expect(text.contains("パネルを開いているとき"))
    }

    @Test("AC-2: スキップの案内は、メニューバーのアイコン→「設定」→「情報」からいつでも開けることを伝え、「アプリ情報」とは書かない")
    func skipNoticeRoute() throws {
        let parts = TutorialModel.skipNoticeParts
        let text = parts.plainText

        #expect(iconCount(parts) == 1)
        #expect(textBeforeIcon(parts)?.hasSuffix("メニューバーの TatakiNote のアイコン") == true)
        #expect(text.contains("チュートリアル"))
        #expect(text.contains("いつでも開けます"))
        let settingsRange = try #require(text.range(of: "「設定」"))
        let appInfoRange = try #require(text.range(of: "「情報」"))
        #expect(settingsRange.lowerBound < appInfoRange.lowerBound)
        #expect(!text.contains("「アプリ情報」"))
    }

    @Test("AC-4: ホットキー未設定の手順1の文はアイコンの部品を1つ含み、ホットキーがあるときは今と同じ文でアイコンを含まない")
    func openPanelInstructionParts() throws {
        try withModel(hasHotkey: false) { model, _ in
            let parts = model.openPanelInstructionParts

            #expect(iconCount(parts) == 1)
            #expect(textBeforeIcon(parts)?.hasSuffix("メニューバーの TatakiNote のアイコン") == true)
            #expect(parts.plainText.contains("設定の「ホットキーとキー操作」"))
            #expect(!parts.plainText.contains("設定の「キー」"))
            #expect(parts.plainText.contains("パネルを開く"))
            #expect(model.openPanelInstruction == parts.plainText)
        }
        try withModel(hasHotkey: true) { model, _ in
            let parts = model.openPanelInstructionParts

            #expect(iconCount(parts) == 0)
            #expect(parts.plainText == "まず下の練習用のチャットの入力欄をクリックします。それから \(hotkey.displayText) を押します。")
        }
    }

    @Test("AC-5: 「メニューバーにアイコンを表示」がオンでもオフでも、案内の文は同じ")
    func hidingMenuBarIconDoesNotChangeText() throws {
        try withModel(hasHotkey: false) { model, settings in
            settings.hidesMenuBarIcon = false
            let openPanelShown = model.openPanelInstructionParts
            let settingsAccessShown = TutorialNextStepIntroduction.settingsAccess.parts
            let skipShown = TutorialModel.skipNoticeParts

            settings.hidesMenuBarIcon = true

            #expect(model.openPanelInstructionParts == openPanelShown)
            #expect(TutorialNextStepIntroduction.settingsAccess.parts == settingsAccessShown)
            #expect(TutorialModel.skipNoticeParts == skipShown)
            #expect(iconCount(model.openPanelInstructionParts) == 1)
            #expect(iconCount(TutorialNextStepIntroduction.settingsAccess.parts) == 1)
            #expect(iconCount(TutorialModel.skipNoticeParts) == 1)
        }
    }

    @Test("AC-6: 文中のアイコンはメニューバーと同じアセットから作られ、テンプレート画像で、指定の高さの正方形になり、元の画像を変えない")
    func inlineImage() throws {
        #expect(MenuBarIcon.assetName == "MenuBarIcon")
        let source = try #require(NSImage(named: MenuBarIcon.assetName))
        let originalSize = source.size

        let image = try #require(MenuBarIcon.inlineImage(height: 16))

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        let sourceAfter = try #require(NSImage(named: MenuBarIcon.assetName))
        #expect(sourceAfter.size == originalSize)
        #expect(sourceAfter.size == NSSize(width: 18, height: 18))
    }
}
