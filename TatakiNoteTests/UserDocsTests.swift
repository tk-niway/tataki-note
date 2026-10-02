import Foundation
import Testing


private struct DocLink: Equatable {
    var target: String
    var line: Int
}

private struct DocLine: Equatable {
    var line: Int
    var text: String
}

private enum UserDocsRules {
    static let readmeName = "README.md"
    static let pagesDirectory = "features"

    static let developerContentPattern = "^## 実装の仕組み|^## 関連ファイル|\\.swift|UserDefaults|plan-[0-9]+"

    static func lines(of markdown: String) -> [Substring] {
        markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    static func links(in markdown: String) -> [DocLink] {
        var result: [DocLink] = []
        for (index, line) in lines(of: markdown).enumerated() {
            var rest = line[...]
            while let open = rest.range(of: "](") {
                let afterOpen = rest[open.upperBound...]
                guard let close = afterOpen.firstIndex(of: ")") else { break }
                let target = afterOpen[..<close].prefix { !$0.isWhitespace }
                result.append(DocLink(target: String(target), line: index + 1))
                rest = afterOpen[afterOpen.index(after: close)...]
            }
        }
        return result
    }

    static func isExternal(_ target: String) -> Bool {
        ["http://", "https://", "mailto:"].contains { target.hasPrefix($0) }
    }

    static func splitTarget(_ target: String) -> (path: String, anchor: String?) {
        var path = target
        var anchor: String?
        if let hash = target.firstIndex(of: "#") {
            path = String(target[..<hash])
            anchor = String(target[target.index(after: hash)...])
        }
        if path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return (path, anchor)
    }

    static func headingText(of line: Substring) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard let first = rest.first, first == " " || first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        if let closing = text.range(of: "\\s+#+$", options: .regularExpression) {
            text.removeSubrange(closing)
        }
        return text
    }

    static func headingIDs(in markdown: String) -> Set<String> {
        var ids: Set<String> = []
        var isInCodeBlock = false
        for line in lines(of: markdown) {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                isInCodeBlock.toggle()
                continue
            }
            if !isInCodeBlock, let heading = headingText(of: line) {
                ids.insert(headingID(for: heading))
            }
        }
        return ids
    }

    static func headingID(for heading: String) -> String {
        var id = ""
        for scalar in heading.lowercased().unicodeScalars {
            if scalar == " " {
                id.append("-")
            } else if scalar == "-" || scalar == "_" || isLetterMarkOrNumber(scalar) {
                id.unicodeScalars.append(scalar)
            }
        }
        return id
    }

    private static func isLetterMarkOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    static func resolve(_ path: String, from page: String) -> String? {
        var components = page.split(separator: "/").dropLast().map(String.init)
        for part in path.split(separator: "/") {
            switch part {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    static func misplacedPages(_ paths: [String]) -> [String] {
        let prefix = pagesDirectory + "/"
        return paths.filter { path in
            guard path != readmeName else { return false }
            guard path.hasPrefix(prefix) else { return true }
            return path.dropFirst(prefix.count).contains("/")
        }.sorted()
    }

    static func unlinkedPages(pageNames: [String], readme: String) -> [String] {
        let linked = Set(links(in: readme).map { splitTarget($0.target).path })
        return pageNames.filter { $0 != readmeName && !linked.contains($0) }.sorted()
    }

    static func brokenLinks(in pages: [String: String], fileExists: (String) -> Bool) -> [String] {
        var problems: [String] = []
        for name in pages.keys.sorted() {
            guard let content = pages[name] else { continue }
            for link in links(in: content) where !link.target.isEmpty && !isExternal(link.target) {
                let (path, anchor) = splitTarget(link.target)
                var targetName = name
                if !path.isEmpty {
                    guard let resolved = resolve(path, from: name) else {
                        problems.append("\(name):\(link.line): \(link.target) — リンク先が docs/ の外です")
                        continue
                    }
                    guard fileExists(resolved) else {
                        problems.append("\(name):\(link.line): \(link.target) — リンク先のファイルがありません")
                        continue
                    }
                    targetName = resolved
                }
                guard let anchor, !anchor.isEmpty, let targetPage = pages[targetName] else { continue }
                let section = anchor.removingPercentEncoding ?? anchor
                if !headingIDs(in: targetPage).contains(section) {
                    problems.append("\(name):\(link.line): \(link.target) — リンク先のページに、ID が「\(section)」の見出しがありません")
                }
            }
        }
        return problems
    }

    static func datedPageNames(_ paths: [String]) -> [String] {
        paths.filter { path in
            let fileName = path.split(separator: "/").last.map(String.init) ?? path
            return fileName.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}-", options: .regularExpression) != nil
        }.sorted()
    }

    static func developerContentLines(in markdown: String) -> [DocLine] {
        lines(of: markdown).enumerated().compactMap { index, line in
            guard line.range(of: developerContentPattern, options: .regularExpression) != nil else { return nil }
            return DocLine(line: index + 1, text: String(line))
        }
    }
}

struct UserDocsTests {
    private static let docsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs")

    private func loadPages() throws -> [String: String] {
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(atPath: Self.docsDirectory.path),
            "\(Self.docsDirectory.path) を読めません"
        )
        var pages: [String: String] = [:]
        for case let path as String in enumerator where path.hasSuffix(".md") {
            let url = Self.docsDirectory.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            pages[path] = try String(contentsOf: url, encoding: .utf8)
        }
        try #require(
            pages.keys.contains { $0.hasPrefix(UserDocsRules.pagesDirectory + "/") },
            "\(Self.docsDirectory.path)/\(UserDocsRules.pagesDirectory) にページが見つかりません"
        )
        return pages
    }

    // MARK: - 実際の docs/

    @Test("AC-1: 目次 README.md があり、README.md 以外のすべてのページが目次からリンクされている")
    func everyPageIsLinkedFromReadme() throws {
        let pages = try loadPages()
        let readme = try #require(pages[UserDocsRules.readmeName], "目次(docs/README.md)がありません")
        #expect(!UserDocsRules.links(in: readme).isEmpty, "目次(README.md)からリンクを1つも取り出せません")

        let unlinked = UserDocsRules.unlinkedPages(pageNames: Array(pages.keys), readme: readme)
        #expect(unlinked.isEmpty, "目次(README.md)からリンクされていないページ: \(unlinked.joined(separator: ", "))")
    }

    @Test("AC-1: README.md 以外のページは docs/features/ の直下にある")
    func pagesAreInFeaturesDirectory() throws {
        let pages = try loadPages()
        let misplaced = UserDocsRules.misplacedPages(Array(pages.keys))
        #expect(misplaced.isEmpty, "docs/features/ の直下に無いページ: \(misplaced.joined(separator: ", "))")
    }

    @Test("AC-2: すべてのページの相対リンクの先のファイルがあり、節へのリンクはリンク先の見出しの ID と一致する")
    func relativeLinksAreNotBroken() throws {
        let pages = try loadPages()
        let relativeLinks = pages.values
            .flatMap { UserDocsRules.links(in: $0) }
            .filter { !UserDocsRules.isExternal($0.target) }
        #expect(!relativeLinks.isEmpty, "docs/ のページから相対リンクを1つも取り出せません")

        let problems = UserDocsRules.brokenLinks(in: pages) { path in
            FileManager.default.fileExists(atPath: Self.docsDirectory.appendingPathComponent(path).path)
        }
        #expect(problems.isEmpty, "切れたリンクがあります:\n\(problems.joined(separator: "\n"))")
    }

    @Test("AC-3: 日付で始まる変更ごとの資料が docs/ に残っていない")
    func noDatedPagesRemain() throws {
        let pages = try loadPages()
        let dated = UserDocsRules.datedPageNames(Array(pages.keys))
        #expect(dated.isEmpty, "日付のファイル名(変更ごとの資料)があります: \(dated.joined(separator: ", "))")
    }

    @Test("AC-4: docs/ のどのページにも、開発者向けの内容(実装の仕組み・関連ファイルの節、.swift、UserDefaults、plan- と数字)が無い")
    func noDeveloperContent() throws {
        let pages = try loadPages()
        var problems: [String] = []
        for name in pages.keys.sorted() {
            for hit in UserDocsRules.developerContentLines(in: pages[name] ?? "") {
                problems.append("\(name):\(hit.line): \(hit.text)")
            }
        }
        #expect(problems.isEmpty, "開発者向けの内容があります:\n\(problems.joined(separator: "\n"))")
    }

    // MARK: - 例の文字列での規則の確かめ

    @Test("AC-5: リンクの取り出し — 相対リンク・節へのリンク・タイトルつきのリンクを取り出し、http などのリンクは外のリンクとして扱う")
    func extractsLinks() {
        let markdown = """
            # 見出し
            [a](a.md) と [b](b.md#見出し) と [外](https://example.com)
            [題つき](c.md "タイトル") [メール](mailto:someone@example.com) [http](http://example.com/x.md)
            角かっこ [だけ] と (かっこ) だけの行
            """

        let links = UserDocsRules.links(in: markdown)
        #expect(links == [
            DocLink(target: "a.md", line: 2),
            DocLink(target: "b.md#見出し", line: 2),
            DocLink(target: "https://example.com", line: 2),
            DocLink(target: "c.md", line: 3),
            DocLink(target: "mailto:someone@example.com", line: 3),
            DocLink(target: "http://example.com/x.md", line: 3),
        ])
        #expect(links.filter { !UserDocsRules.isExternal($0.target) }.map(\.target) == ["a.md", "b.md#見出し", "c.md"])
        #expect(UserDocsRules.links(in: "リンクの無い文章").isEmpty)
    }

    @Test("AC-5: 見出しの ID — 日本語と記号を含む見出しから、GitHub と同じ規則で ID を作る")
    func makesHeadingIDs() {
        let cases: [(heading: String, id: String)] = [
            ("パネルを開く・閉じる", "パネルを開く閉じる"),
            ("Step 1 (設定)", "step-1-設定"),
            ("確定キーと確定+送信キー", "確定キーと確定送信キー"),
            ("`⌘L` で行を選ぶ", "l-で行を選ぶ"),
            ("snake_case と kebab-case", "snake_case-と-kebab-case"),
            ("「確定」の動き", "確定の動き"),
        ]
        for (heading, id) in cases {
            #expect(UserDocsRules.headingID(for: heading) == id, "見出し「\(heading)」")
        }

        let markdown = """
            # 入力パネル
            ## パネルを開く・閉じる
            ### Step 1 (設定) ###
            #ハッシュタグは見出しではない
            ####### 7 つは見出しではない
            ```
            # コードブロックの中は見出しではない
            ```
            """
        #expect(UserDocsRules.headingIDs(in: markdown) == ["入力パネル", "パネルを開く閉じる", "step-1-設定"])
    }

    @Test("AC-5: 切れたリンクの検出 — 無いファイル・無い見出しへのリンクを見逃さず、正しいリンクは問題にしない")
    func detectsBrokenLinks() {
        let pages = [
            "README.md": """
                # 目次
                [a](a.md)
                [a の節](a.md#使い方)
                [無いページ](missing.md)
                [無い節](a.md#無い見出し)
                [外](https://example.com/missing.md)
                [自分の節](#目次)
                [自分の無い節](#無い)
                [同じフォルダ](./a.md#使い方)
                """,
            "a.md": """
                # A
                ## 使い方
                [エンコードした節](README.md#%E7%9B%AE%E6%AC%A1)
                """,
        ]

        let problems = UserDocsRules.brokenLinks(in: pages) { pages.keys.contains($0) }
        #expect(problems.count == 3, "\(problems)")
        #expect(problems.contains { $0.hasPrefix("README.md:4: missing.md") })
        #expect(problems.contains { $0.hasPrefix("README.md:5: a.md#無い見出し") })
        #expect(problems.contains { $0.hasPrefix("README.md:8: #無い") })
    }

    @Test("AC-5: リンク先の辿り方 — ページのフォルダから辿り、docs/ の外に出るものを見分ける")
    func resolvesLinksFromPageDirectory() {
        #expect(UserDocsRules.resolve("features/panel.md", from: "README.md") == "features/panel.md")
        #expect(UserDocsRules.resolve("settings.md", from: "features/panel.md") == "features/settings.md")
        #expect(UserDocsRules.resolve("./settings.md", from: "features/panel.md") == "features/settings.md")
        #expect(UserDocsRules.resolve("../README.md", from: "features/panel.md") == "README.md")
        #expect(UserDocsRules.resolve("../../x.md", from: "features/panel.md") == nil)
        #expect(UserDocsRules.resolve("../x.md", from: "README.md") == nil)
    }

    @Test("AC-5: 切れたリンクの検出(features/ の中のページ) — 同じフォルダ・目次へのリンクを辿り、外へのリンクを見逃さない")
    func detectsBrokenLinksFromFeaturesPages() {
        let pages = [
            "README.md": """
                # 目次
                [パネル](features/panel.md#開く)
                [無いページ](panel.md)
                """,
            "features/panel.md": """
                # パネル
                ## 開く
                [設定](settings.md#ホットキー) [目次](../README.md#目次)
                [無い節](settings.md#無い) [外](../../etc.md)
                """,
            "features/settings.md": """
                # 設定
                ## ホットキー
                """,
        ]

        let problems = UserDocsRules.brokenLinks(in: pages) { pages.keys.contains($0) }
        #expect(problems.count == 3, "\(problems)")
        #expect(problems.contains { $0.hasPrefix("README.md:3: panel.md") })
        #expect(problems.contains { $0.hasPrefix("features/panel.md:4: settings.md#無い") })
        #expect(problems.contains { $0.hasPrefix("features/panel.md:4: ../../etc.md") && $0.hasSuffix("docs/ の外です") })
    }

    @Test("AC-5: ページの置き場所の検出 — features/ の直下に無いページを見逃さない")
    func detectsMisplacedPages() {
        let paths = ["README.md", "features/panel.md", "panel.md", "features/sub/deep.md", "other/x.md"]
        #expect(UserDocsRules.misplacedPages(paths) == ["features/sub/deep.md", "other/x.md", "panel.md"])
    }

    @Test("AC-5: 目次からリンクされていないページの検出 — README.md に無いページを見逃さない")
    func detectsPagesNotLinkedFromReadme() {
        let readme = """
            # 目次
            - [a](a.md)
            - [b の節](./b.md#節)
            """
        let unlinked = UserDocsRules.unlinkedPages(pageNames: ["README.md", "a.md", "b.md", "c.md"], readme: readme)
        #expect(unlinked == ["c.md"])

        let featuresReadme = """
            # 目次
            - [パネル](features/panel.md#開く)
            - [設定](./features/settings.md)
            - [同じ名前でもフォルダが違う](other.md)
            """
        let featurePages = ["README.md", "features/panel.md", "features/settings.md", "features/other.md"]
        #expect(UserDocsRules.unlinkedPages(pageNames: featurePages, readme: featuresReadme) == ["features/other.md"])
    }

    @Test("AC-5: 日付のファイル名の検出 — 変更ごとの資料の名前を見逃さない")
    func detectsDatedPageNames() {
        let names = [
            "2026-09-25-x.md", "features/2026-09-26-w.md", "features/panel.md", "README.md",
            "2026-9-25-y.md", "notes-2026-09-25-z.md",
        ]
        #expect(UserDocsRules.datedPageNames(names) == ["2026-09-25-x.md", "features/2026-09-26-w.md"])
    }

    @Test("AC-5: 開発者向けの語の検出 — ファイル名・保存の場所・プランの番号・開発者向けの節を見逃さない")
    func detectsDeveloperContent() {
        let markdown = """
            # 使い方
            - 型は `Foo.swift` にある
            plan-6 で足した
            設定は UserDefaults に保存する
            ## 実装の仕組み(開発者向け)
            ## 関連ファイル
            - 行の途中の ## 実装の仕組み は対象にしない
            - plan-B や swift という言葉だけの行
            """
        let hits = UserDocsRules.developerContentLines(in: markdown)
        #expect(hits.map(\.line) == [2, 3, 4, 5, 6])
        #expect(hits.first == DocLine(line: 2, text: "- 型は `Foo.swift` にある"))
    }
}
