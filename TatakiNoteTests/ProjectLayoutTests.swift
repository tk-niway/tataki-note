import Foundation
import Testing

struct ProjectLayoutTests {
    private static let testDoublesPrefix = "TestDoubles/"
    private static let layoutTestsFile = "ProjectLayoutTests.swift"
    private static let declarationKeywords: Set<String> = [
        "class", "struct", "enum", "actor", "protocol", "func", "extension",
    ]
    private static let modifierKeywords: Set<String> = [
        "nonisolated", "final", "private", "fileprivate", "public", "internal",
    ]
    private static let typeKeywords: Set<String> = [
        "class", "struct", "enum", "actor", "protocol",
    ]
    private static let documentAndRuleTests: Set<String> = [
        "UserDocsTests", "UserDocsWordingTests", "DistributionDocsTests",
        "SettingsDocsTests", "TestStorageRuleTests", "ProjectLayoutTests",
        "PublicCheckSecretsTests", "ReleaseAppcastSigningTests", "ReleaseHardeningTests",
    ]
    private static let appRootFiles: Set<String> = ["MyApp.swift", "AppDelegate.swift"]
    private static let featureFolders: Set<String> = [
        "App", "AutoShow", "Drafts", "Export", "Insertion", "InsertionTarget", "Keys",
        "Panel", "Panel/Editor", "Panel/Frame", "Permission", "Settings", "Shared",
        "Storage", "Tutorial", "Updates",
    ]

    private struct TopLevelDeclaration {
        let keyword: String
        let name: String
        let isPrivate: Bool
    }

    private static func testFiles() throws -> [String] {
        try TestSourceFiles.swiftFiles(in: TestSourceFiles.testsDirectory)
    }

    private static func source(of file: String) throws -> String {
        let url = TestSourceFiles.testsDirectory.appendingPathComponent(file)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) を読めません"
        )
    }

    private static func source(at url: URL) throws -> String {
        try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) を読めません"
        )
    }

    private static func fileStem(_ file: String) -> String {
        URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func topLevelDeclarations(in source: String) -> [TopLevelDeclaration] {
        var declarations: [TopLevelDeclaration] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != " ", first != "\t" else { continue }
            var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            var isPrivate = false
            while let token = tokens.first {
                if token.hasPrefix("@") {
                    tokens.removeFirst()
                } else if Self.modifierKeywords.contains(token) {
                    if token == "private" || token == "fileprivate" {
                        isPrivate = true
                    }
                    tokens.removeFirst()
                } else {
                    break
                }
            }
            guard tokens.count >= 2, Self.declarationKeywords.contains(tokens[0]) else { continue }
            let name = String(tokens[1].prefix(while: Self.isIdentifierCharacter))
            guard !name.isEmpty || tokens[0] == "extension" else { continue }
            declarations.append(TopLevelDeclaration(keyword: tokens[0], name: name, isPrivate: isPrivate))
        }
        return declarations
    }

    private static func contains(word: String, in source: String) -> Bool {
        var searchStart = source.startIndex
        while let range = source.range(of: word, range: searchStart..<source.endIndex) {
            let before = range.lowerBound == source.startIndex ? nil : source[source.index(before: range.lowerBound)]
            let after = range.upperBound == source.endIndex ? nil : source[range.upperBound]
            let isBoundaryBefore = before.map { !isIdentifierCharacter($0) } ?? true
            let isBoundaryAfter = after.map { !isIdentifierCharacter($0) } ?? true
            if isBoundaryBefore && isBoundaryAfter {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func conformingTypes(to protocolName: String, in source: String) -> [String] {
        let typeKeywords = ["class", "struct", "enum", "actor"]
        var names: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            guard let colon = text.firstIndex(of: ":") else { continue }
            let head = text[text.startIndex..<colon]
            let tail = text[text.index(after: colon)...]
            guard let keyword = typeKeywords.first(where: { contains(word: $0, in: String(head)) }),
                  contains(word: protocolName, in: String(tail))
            else { continue }
            let afterKeyword = head.components(separatedBy: keyword).last ?? ""
            let name = afterKeyword.trimmingCharacters(in: .whitespaces)
            names.append(name.isEmpty ? keyword : name)
        }
        return names
    }

    @Test("AC-1: 単体テストのファイルの一覧は TestDoubles/ の下も含み、TestStorageRuleTests はその一覧を調べる")
    func testSourceFilesIncludeTestDoubles() throws {
        let files = try Self.testFiles()
        #expect(files.contains("TestDoubles/InMemoryDefaults.swift"), "TestDoubles/InMemoryDefaults.swift が一覧にありません")
        #expect(files.contains("TestStorageRuleTests.swift"), "TestStorageRuleTests.swift が一覧にありません")

        let storageRule = try Self.source(of: "TestStorageRuleTests.swift")
        #expect(storageRule.contains("TestSourceFiles.swiftFiles(in:"), "TestStorageRuleTests が TestSourceFiles の一覧を使っていません")
        #expect(!storageRule.contains("contentsOfDirectory"), "TestStorageRuleTests が直下のファイルだけを調べています")
    }

    @Test("AC-2: TestDoubles/ の外の単体テストのファイルは、どれも @Test を1つ以上含む")
    func everyTestFileContainsATest() throws {
        let files = try Self.testFiles().filter { !$0.hasPrefix(Self.testDoublesPrefix) }
        #expect(!files.isEmpty, "単体テストのファイルがありません")

        var withoutTests: [String] = []
        for file in files {
            if !(try Self.source(of: file)).contains("@Test") {
                withoutTests.append(file)
            }
        }
        #expect(withoutTests.isEmpty, "@Test を含まないファイルがあります: \(withoutTests.joined(separator: ", "))")
    }

    @Test("AC-3: 複数のテストのファイルから使う偽物・補助は TestDoubles/ の下にだけ宣言されている")
    func sharedDoublesLiveInTestDoubles() throws {
        let files = try Self.testFiles()
        let sources = try Dictionary(uniqueKeysWithValues: files.map { ($0, try Self.source(of: $0)) })
        let testFiles = files.filter { !$0.hasPrefix(Self.testDoublesPrefix) }

        var violations: [String] = []
        for file in testFiles where file != Self.layoutTestsFile {
            let declarations = Self.topLevelDeclarations(in: sources[file] ?? "")
            for declaration in declarations where !declaration.isPrivate {
                if declaration.keyword == "extension" {
                    violations.append("\(file): extension \(declaration.name)")
                    continue
                }
                let users = files
                    .filter { $0 != file && $0 != Self.layoutTestsFile }
                    .filter { Self.contains(word: declaration.name, in: sources[$0] ?? "") }
                if !users.isEmpty {
                    violations.append("\(file): \(declaration.name)(\(users.joined(separator: ", ")))")
                }
            }
        }
        #expect(
            violations.isEmpty,
            "複数のファイルから使う宣言は TestDoubles/ に置いてください: \(violations.joined(separator: " / "))"
        )
    }

    @Test("AC-4: 同じ役割の偽物は TestDoubles/ に1つだけ宣言され、まとめる前の名前は残っていない")
    func duplicateDoublesAreMerged() throws {
        let files = try Self.testFiles().filter { $0 != Self.layoutTestsFile }
        let sources = try Dictionary(uniqueKeysWithValues: files.map { ($0, try Self.source(of: $0)) })

        for protocolName in ["ExportDestinationChoosing", "TextSharing", "UpdaterDriving"] {
            var conformances: [String] = []
            for file in files {
                for name in Self.conformingTypes(to: protocolName, in: sources[file] ?? "") {
                    conformances.append("\(file): \(name)")
                }
            }
            #expect(conformances.count == 1, "\(protocolName) に準拠する偽物が1つではありません: \(conformances.joined(separator: ", "))")
            #expect(
                conformances.allSatisfy { $0.hasPrefix(Self.testDoublesPrefix) },
                "\(protocolName) に準拠する偽物は TestDoubles/ に置いてください: \(conformances.joined(separator: ", "))"
            )
        }

        for name in ["HeldSleeper", "MonitorBox", "FakeHotkeyController"] {
            var declarations: [String] = []
            for file in files {
                let matches = Self.topLevelDeclarations(in: sources[file] ?? "").filter { $0.name == name }
                declarations.append(contentsOf: matches.map { _ in file })
            }
            #expect(declarations.count == 1, "\(name) の宣言が1つではありません: \(declarations.joined(separator: ", "))")
        }

        let retiredNames = [
            "RowChooserSpy", "FakeDestinationChooser", "ShareChooserSpy", "RowSharerSpy",
            "RowHeldSleeper", "ShareHeldSleeper", "SettingsFakeUpdater", "InertDriver", "HotkeyRecorder",
        ]
        var leftovers: [String] = []
        for file in files {
            for name in retiredNames where Self.contains(word: name, in: sources[file] ?? "") {
                leftovers.append("\(file): \(name)")
            }
        }
        #expect(leftovers.isEmpty, "まとめる前の名前が残っています: \(leftovers.joined(separator: ", "))")
    }

    @Test("AC-5: 単体テストのファイルは、ファイル名と同じ名前のスイートを1つだけ宣言している")
    func everyTestFileDeclaresOneSuiteNamedLikeTheFile() throws {
        let files = try Self.testFiles().filter { !$0.hasPrefix(Self.testDoublesPrefix) }
        #expect(!files.isEmpty, "単体テストのファイルがありません")

        var violations: [String] = []
        for file in files {
            let suites = Self.topLevelDeclarations(in: try Self.source(of: file))
                .filter { Self.typeKeywords.contains($0.keyword) && $0.name.hasSuffix("Tests") }
                .map(\.name)
            if suites != [Self.fileStem(file)] {
                violations.append("\(file): \(suites.joined(separator: ", "))")
            }
        }
        #expect(
            violations.isEmpty,
            "ファイル名と同じ名前のスイートを1つだけ宣言してください: \(violations.joined(separator: " / "))"
        )
    }

    @Test("AC-6: 単体テストのファイル名は、資料・規則・スクリプトを確かめるものを除いて、アプリの型かソースのファイルの名前で始まる")
    func testFileNamesStartWithAppTypeOrSourceFileName() throws {
        let appDirectory = TestSourceFiles.appSourceDirectory
        var names: Set<String> = []
        for file in try TestSourceFiles.swiftFiles(in: appDirectory) {
            names.insert(Self.fileStem(file))
            let source = try Self.source(at: appDirectory.appendingPathComponent(file))
            for declaration in Self.topLevelDeclarations(in: source) where Self.typeKeywords.contains(declaration.keyword) {
                names.insert(declaration.name)
            }
        }
        #expect(!names.isEmpty, "アプリのソースの型が見つかりません")

        let files = try Self.testFiles().filter { !$0.hasPrefix(Self.testDoublesPrefix) }
        var violations: [String] = []
        for file in files {
            let stem = Self.fileStem(file)
            if Self.documentAndRuleTests.contains(stem) { continue }
            let base = stem.hasSuffix("Tests") ? String(stem.dropLast("Tests".count)) : stem
            let matches = names.contains { name in
                guard base.hasPrefix(name) else { return false }
                guard base.count > name.count else { return true }
                let next = base[base.index(base.startIndex, offsetBy: name.count)]
                return next.isUppercase
            }
            if !matches {
                violations.append(file)
            }
        }
        #expect(
            violations.isEmpty,
            "アプリの型かソースのファイルの名前で始まる名前にしてください: \(violations.joined(separator: ", "))"
        )
    }

    @Test("AC-8: アプリのソースの直下は MyApp.swift と AppDelegate.swift だけで、他は決めた機能のフォルダにあり、どのフォルダも空でない")
    func appSourcesLiveInFeatureFolders() throws {
        let files = try TestSourceFiles.swiftFiles(in: TestSourceFiles.appSourceDirectory)
        #expect(!files.isEmpty, "アプリのソースがありません")

        var rootFiles: Set<String> = []
        var outsideFolders: [String] = []
        var filledFolders: Set<String> = []
        for file in files {
            guard let slash = file.lastIndex(of: "/") else {
                rootFiles.insert(file)
                continue
            }
            let folder = String(file[file.startIndex..<slash])
            if Self.featureFolders.contains(folder) {
                filledFolders.insert(folder)
            } else {
                outsideFolders.append(file)
            }
        }

        #expect(rootFiles == Self.appRootFiles, "直下の Swift のファイルが MyApp.swift・AppDelegate.swift だけではありません: \(rootFiles.sorted().joined(separator: ", "))")
        #expect(outsideFolders.isEmpty, "決めたフォルダの外にあるファイルがあります: \(outsideFolders.joined(separator: ", "))")
        let emptyFolders = Self.featureFolders.subtracting(filledFolders)
        #expect(emptyFolders.isEmpty, "Swift のファイルが無いフォルダがあります: \(emptyFolders.sorted().joined(separator: ", "))")
    }

    @Test("AC-9: CLAUDE.md の「構成」の表のフォルダは、アプリのソースの機能のフォルダと同じで、Models/・Views/ は載っていない")
    func claudeMdListsTheFeatureFolders() throws {
        let text = try Self.source(at: TestSourceFiles.repositoryRoot.appendingPathComponent("CLAUDE.md"))

        let rowPrefix = "| `TatakiNote/"
        var listed: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix(rowPrefix) {
            let rest = line.dropFirst(rowPrefix.count)
            guard let end = rest.range(of: "/`") else { continue }
            listed.insert(String(rest[rest.startIndex..<end.lowerBound]))
        }

        #expect(
            listed == Self.featureFolders,
            "「構成」の表のフォルダが機能のフォルダと違います。表にだけ: \(listed.subtracting(Self.featureFolders).sorted().joined(separator: ", ")) / 表に無い: \(Self.featureFolders.subtracting(listed).sorted().joined(separator: ", "))"
        )
        #expect(!text.contains("TatakiNote/Models/"), "CLAUDE.md に TatakiNote/Models/ が残っています")
        #expect(!text.contains("TatakiNote/Views/"), "CLAUDE.md に TatakiNote/Views/ が残っています")
    }
}
