import Foundation
import Testing
@testable import TatakiNote

struct SettingsSectionNameTests {
    private static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TatakiNote")

    private static let oldName = "開き方とキー"
    private static let newReference = "設定の「ホットキーとキー操作」"

    @Test("AC-2: アプリのソースのどの .swift にも、旧い名前「開き方とキー」が残っていない")
    func noOldNameInSources() throws {
        let enumerator = try #require(
            FileManager.default.enumerator(atPath: Self.sourceDirectory.path),
            "\(Self.sourceDirectory.path) を読めません"
        )
        var hits: [String] = []
        var count = 0
        for case let path as String in enumerator where path.hasSuffix(".swift") {
            count += 1
            let text = try String(contentsOf: Self.sourceDirectory.appendingPathComponent(path), encoding: .utf8)
            if text.contains(Self.oldName) {
                hits.append(path)
            }
        }
        #expect(count > 0, "ソースが1つも見つかりません")
        #expect(hits.isEmpty, "旧い名前が残っているファイル: \(hits.sorted().joined(separator: ", "))")
    }

    @Test("AC-2: チュートリアルの紹介と練習用のチャットの返事は、設定の「ホットキーとキー操作」を案内する")
    func tutorialAndChatTextsPointToNewName() {
        let reply = PracticeChatReply.text(for: .commitThenReturn, commitAndSendKey: nil, hotkey: "⌥⇧Space")

        #expect(TutorialNextStepIntroduction.hotkeyChange.text.contains(Self.newReference))
        #expect(reply.contains(Self.newReference))
    }
}
