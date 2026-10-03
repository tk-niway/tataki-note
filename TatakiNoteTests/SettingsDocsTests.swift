import Foundation
import Testing
@testable import TatakiNote

struct SettingsDocsTests {
    private static let docsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs")

    private static let settingsPage = "features/settings.md"
    private static let insertAndSendPage = "features/insert-and-send.md"

    private func loadPages() throws -> [String: String] {
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(atPath: Self.docsDirectory.path),
            "\(Self.docsDirectory.path) を読めません"
        )
        var pages: [String: String] = [:]
        for case let path as String in enumerator where path.hasSuffix(".md") {
            pages[path] = try String(
                contentsOf: Self.docsDirectory.appendingPathComponent(path),
                encoding: .utf8
            )
        }
        try #require(pages[Self.settingsPage] != nil, "\(Self.settingsPage) がありません")
        return pages
    }

    @Test("AC-11: 設定のページの「一般の項目」「キーの項目」「パネルの項目」「アプリ情報の項目」の見出しが、サイドバーと同じ順に並ぶ")
    func sectionHeadingsFollowSidebarOrder() throws {
        let pages = try loadPages()
        let settings = try #require(pages[Self.settingsPage])
        let headings = settings
            .split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
        let expected = SettingsSection.allCases.map { "\($0.displayName)の項目" }

        #expect(expected == ["一般の項目", "キーの項目", "パネルの項目", "アプリ情報の項目"])
        let found = headings.filter { expected.contains($0) }
        #expect(found == expected, "見出しの並び: \(found)")
    }

    @Test("AC-11: docs/ のどのページにも「エディタ設定」が無い")
    func noRemovedSectionName() throws {
        let pages = try loadPages()
        let hits = pages.keys.sorted().filter { pages[$0]?.contains("エディタ設定") == true }
        #expect(hits.isEmpty, "「エディタ設定」が残っているページ: \(hits.joined(separator: ", "))")
    }

    @Test("AC-11: キー・パネルの項目の場所を「一般」と書く古い書き方が、docs/ のどのページにも無い")
    func noOldPlacementWording() throws {
        let pages = try loadPages()
        let oldWordings = [
            "設定の「一般」で設定",
            "設定の「一般」で登録",
            "「一般」→「パネルを出す位置」",
            "「一般」でそのキーを登録",
            "「一般」で確かめられます",
        ]
        var problems: [String] = []
        for name in pages.keys.sorted() {
            for wording in oldWordings where pages[name]?.contains(wording) == true {
                problems.append("\(name): \(wording)")
            }
        }
        #expect(problems.isEmpty, "古い場所の書き方が残っています:\n\(problems.joined(separator: "\n"))")
    }

    @Test("AC-11: 挿入と送信のページは、キーの登録先として「キーの項目」へリンクし、「一般の項目」へはリンクしない")
    func insertAndSendLinksToKeySection() throws {
        let pages = try loadPages()
        let page = try #require(pages[Self.insertAndSendPage], "\(Self.insertAndSendPage) がありません")

        #expect(page.contains("settings.md#キーの項目"))
        #expect(!page.contains("settings.md#一般の項目"))
    }

    @Test("AC-11: 設定のページのショートカットキーの説明文は、アプリの文字列と一字一句同じ")
    func shortcutDescriptionMatchesApp() throws {
        let pages = try loadPages()
        let settings = try #require(pages[Self.settingsPage])

        #expect(settings.contains(EditorShortcuts.settingDescription))
    }
}
