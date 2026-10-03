import Foundation
import Testing


private struct WordingHit: Equatable {
    var page: String
    var line: Int
    var term: String
}

private enum UserDocsWordingRules {
    static let readmePath = "README.md"
    static let guideIndexPath = "docs/README.md"
    static let settingsPath = "docs/features/settings.md"
    static let insertAndSendPath = "docs/features/insert-and-send.md"
    static let panelPath = "docs/features/panel.md"
    static let accessibilityPath = "docs/features/accessibility.md"

    static let hidingMessage = "⌘H はパネルを閉じるキーのため、登録できません。"
    static let editingReason = "編集ショートカットで使っているため"

    static let forbiddenTerms = [
        "確定キー", "確定送信キー", "既定値", "初期設定", "文章で伸びた高さ", "「権限」",
        "| 確定 |", "確定(挿入だけ", "確定(または確定+送信)", "確定・確定+送信", "↩ 確定」",
    ]

    static let requiredPhrases: [(page: String, phrase: String)] = [
        (insertAndSendPath, "| 確定+挿入 |"),
        (insertAndSendPath, "確定+挿入(挿入だけ。Enter は送りません)"),
        (insertAndSendPath, "確定+挿入(または確定+送信)"),
        (insertAndSendPath, "初期値(確定+挿入は"),
        (settingsPath, "確定+挿入(または確定+送信)"),
        (settingsPath, "確定+挿入・確定+送信にはなりません"),
        (guideIndexPath, "閉じる・改行・確定+挿入・確定+送信"),
        (accessibilityPath, "挿入(確定+挿入・確定+送信。"),
        (panelPath, "⇧⌘↩ 確定+挿入"),
    ]

    static func lines(of markdown: String) -> [String] {
        markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    static func removingLinkTargets(from line: String) -> String {
        var result = ""
        var rest = line[...]
        while let open = rest.range(of: "](") {
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.firstIndex(of: ")") else { break }
            result += rest[..<open.upperBound]
            result += ")"
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        result += rest
        return result
    }

    static func hits(in pages: [String: String], terms: [String]) -> [WordingHit] {
        var result: [WordingHit] = []
        for name in pages.keys.sorted() {
            for (index, line) in lines(of: pages[name] ?? "").enumerated() {
                let text = removingLinkTargets(from: line)
                for term in terms where text.contains(term) {
                    result.append(WordingHit(page: name, line: index + 1, term: term))
                }
            }
        }
        return result
    }

    static func linesMentioningEditingReason(in markdown: String) -> [String] {
        lines(of: markdown).filter { $0.contains(editingReason) }
    }
}

struct UserDocsWordingTests {
    private static let rootDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func loadPages() throws -> [String: String] {
        var pages: [String: String] = [:]
        for path in [UserDocsWordingRules.readmePath, UserDocsWordingRules.guideIndexPath] {
            let url = Self.rootDirectory.appendingPathComponent(path)
            pages[path] = try String(contentsOf: url, encoding: .utf8)
        }
        let featuresDirectory = Self.rootDirectory.appendingPathComponent("docs/features")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: featuresDirectory.path)
            .filter { $0.hasSuffix(".md") }
        try #require(!names.isEmpty, "\(featuresDirectory.path) にページが見つかりません")
        for name in names {
            let url = featuresDirectory.appendingPathComponent(name)
            pages["docs/features/\(name)"] = try String(contentsOf: url, encoding: .utf8)
        }
        return pages
    }

    // MARK: - 実際の docs/ と README.md

    @Test("AC-10: 利用ガイドと README の本文(リンクの行き先を除く)に、古い呼び名・古い説明が無い")
    func noOutdatedWording() throws {
        let pages = try loadPages()
        #expect(pages[UserDocsWordingRules.guideIndexPath] != nil, "目次(docs/README.md)を読めていません")
        #expect(pages[UserDocsWordingRules.readmePath] != nil, "README.md を読めていません")

        let hits = UserDocsWordingRules.hits(in: pages, terms: UserDocsWordingRules.forbiddenTerms)
        let report = hits.map { "\($0.page):\($0.line): 「\($0.term)」" }.joined(separator: "\n")
        #expect(hits.isEmpty, "古い語が残っています:\n\(report)")
    }

    @Test("AC-10: 設定のページの「受け付けない理由」の表は、⌘H を編集ショートカットに含めず、パネルを閉じるキーとして書いている")
    func hidingKeyIsDocumentedAsClosingKey() throws {
        let pages = try loadPages()
        let settings = try #require(pages[UserDocsWordingRules.settingsPath], "設定のページを読めていません")

        #expect(settings.contains(UserDocsWordingRules.hidingMessage))

        let editingLines = UserDocsWordingRules.linesMentioningEditingReason(in: settings)
        #expect(!editingLines.isEmpty, "編集ショートカットの理由の行がありません")
        for line in editingLines {
            #expect(!line.contains("⌘H"), "編集ショートカットの理由の行に ⌘H があります: \(line)")
        }
    }

    @Test("AC-10: 「確定」を「確定+挿入」にした箇所に、新しい語がある")
    func renamedCommitWordingIsPresent() throws {
        let pages = try loadPages()
        var missing: [String] = []
        for (page, phrase) in UserDocsWordingRules.requiredPhrases {
            guard let content = pages[page] else {
                missing.append("\(page): ページを読めません")
                continue
            }
            if !content.contains(phrase) {
                missing.append("\(page): 「\(phrase)」")
            }
        }
        #expect(missing.isEmpty, "あるはずの語がありません:\n\(missing.joined(separator: "\n"))")
    }

    // MARK: - 例の文字列での規則の確かめ

    @Test("AC-10: リンクの行き先の取り除き — 本文の古い語は拾い、リンクの行き先の ID に含まれる語は拾わない")
    func linkTargetsAreIgnored() {
        let line = "[確定+挿入キーと確定+送信キーを登録する](settings.md#確定挿入キーと確定送信キーを登録する) と (括弧) と [別](b.md)"
        let stripped = UserDocsWordingRules.removingLinkTargets(from: line)
        #expect(stripped == "[確定+挿入キーと確定+送信キーを登録する]() と (括弧) と [別]()")

        let pages = [
            "a.md": "[見出し](a.md#確定挿入キーと確定送信キーを登録する)\n本文に確定送信キーがある\n[確定送信キー](b.md)",
        ]
        let hits = UserDocsWordingRules.hits(in: pages, terms: ["確定送信キー"])
        #expect(hits == [
            WordingHit(page: "a.md", line: 2, term: "確定送信キー"),
            WordingHit(page: "a.md", line: 3, term: "確定送信キー"),
        ])
    }

    @Test("AC-10: 古い語の検出 — 古い呼び名を見逃さず、新しい呼び名は拾わない")
    func detectsOutdatedWording() {
        let pages = [
            "old.md": "確定キーを押す\n既定値と初期設定\n| 確定 | 挿入 |\n確定(または確定+送信)する\n確定・確定+送信\n「⇧⌘↩ 確定」",
            "new.md": "確定+挿入キーを押す\n初期値\n| 確定+挿入 | 挿入 |\n確定+挿入(または確定+送信)する\n確定+挿入・確定+送信\n「⇧⌘↩ 確定+挿入」",
        ]
        let hits = UserDocsWordingRules.hits(in: pages, terms: UserDocsWordingRules.forbiddenTerms)
        #expect(hits.allSatisfy { $0.page == "old.md" }, "\(hits)")
        #expect(hits.map(\.term) == [
            "確定キー", "既定値", "初期設定", "| 確定 |", "確定(または確定+送信)", "確定・確定+送信", "↩ 確定」",
        ])
        #expect(hits.map(\.line) == [1, 2, 2, 3, 4, 5, 6])
    }

    @Test("AC-10: 編集ショートカットの理由の行の取り出し — 理由を含む行だけを取り出す")
    func extractsEditingReasonLines() {
        let markdown = """
            | `⌘H` | 「⌘H はパネルを閉じるキーのため、登録できません。」 |
            | `⌘A` | 「(そのキー) は入力欄の編集ショートカットで使っているため、登録できません。」 |
            """
        let found = UserDocsWordingRules.linesMentioningEditingReason(in: markdown)
        #expect(found.count == 1)
        #expect(found.first?.contains("⌘A") == true)
    }
}
