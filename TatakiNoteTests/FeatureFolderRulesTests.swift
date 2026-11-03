import Foundation
import Testing

struct FeatureFolderRulesTests {
    private static let insertionFolder = "Insertion"
    private static let insertionTargetFolder = "InsertionTarget"
    private static let panelFolder = "Panel"
    private static let autoShowFolder = "AutoShow"
    private static let removedSenderName = "EnterKeySender"
    private static let typeKeywords: Set<String> = ["class", "struct", "enum", "actor", "protocol"]
    private static let modifierKeywords: Set<String> = [
        "nonisolated", "final", "private", "fileprivate", "public", "internal",
    ]

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func folderFiles(_ folder: String, includingSubfolders: Bool) throws -> [String] {
        let prefix = folder + "/"
        return try TestSourceFiles.swiftFiles(in: TestSourceFiles.appSourceDirectory).filter { file in
            guard file.hasPrefix(prefix) else { return false }
            return includingSubfolders || !file.dropFirst(prefix.count).contains("/")
        }
    }

    private static func source(of file: String) throws -> String {
        let url = TestSourceFiles.appSourceDirectory.appendingPathComponent(file)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) を読めません"
        )
    }

    private static func declaredTypeNames(in source: String) -> Set<String> {
        var names: Set<String> = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != " ", first != "\t" else { continue }
            var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            while let token = tokens.first, token.hasPrefix("@") || modifierKeywords.contains(token) {
                tokens.removeFirst()
            }
            guard tokens.count >= 2, typeKeywords.contains(tokens[0]) else { continue }
            let name = String(tokens[1].prefix(while: isIdentifierCharacter))
            if !name.isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    private static func declaredTypeNames(inFolder folder: String, includingSubfolders: Bool) throws -> Set<String> {
        var names: Set<String> = []
        for file in try folderFiles(folder, includingSubfolders: includingSubfolders) {
            names.formUnion(declaredTypeNames(in: try source(of: file)))
        }
        return names
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
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

    private static func usedNames(inFolder folder: String, from names: Set<String>) throws -> [String] {
        var used: [String] = []
        for file in try folderFiles(folder, includingSubfolders: false) {
            let text = try source(of: file)
            for name in names.sorted() where containsWord(name, in: text) {
                used.append("\(file): \(name)")
            }
        }
        return used
    }

    private static func fileStem(_ file: String) -> String {
        URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    }

    @Test("AC-3: Insertion/ の各ファイルは、ファイル名と同じ名前の型を宣言し、アプリとテストのソースに EnterKeySender の名前が無い")
    func insertionFilesDeclareTheTypeNamedAfterThem() throws {
        let files = try Self.folderFiles(Self.insertionFolder, includingSubfolders: false)
        #expect(!files.isEmpty, "\(Self.insertionFolder)/ の直下にファイルがありません")

        var violations: [String] = []
        for file in files {
            let declared = Self.declaredTypeNames(in: try Self.source(of: file))
            if !declared.contains(Self.fileStem(file)) {
                violations.append(file)
            }
        }
        #expect(violations.isEmpty, "ファイル名と同じ名前の型が無いファイル: \(violations)")

        let thisFile = "FeatureFolderRulesTests.swift"
        var remaining: [String] = []
        for file in try TestSourceFiles.swiftFiles(in: TestSourceFiles.appSourceDirectory) {
            let text = try Self.source(of: file)
            if Self.containsWord(Self.removedSenderName, in: text) {
                remaining.append("TatakiNote/\(file)")
            }
        }
        for file in try TestSourceFiles.swiftFiles(in: TestSourceFiles.testsDirectory) where file != thisFile {
            let url = TestSourceFiles.testsDirectory.appendingPathComponent(file)
            let text = try #require(try? String(contentsOf: url, encoding: .utf8), "\(url.path) を読めません")
            if Self.containsWord(Self.removedSenderName, in: text) {
                remaining.append("TatakiNoteTests/\(file)")
            }
        }
        #expect(remaining.isEmpty, "\(Self.removedSenderName) の名前が残っているファイル: \(remaining)")
    }

    @Test("AC-1: Insertion/ のファイルは、InsertionTarget/ と Panel/(下のフォルダを含む)で宣言された型を使わない")
    func insertionDoesNotUseInsertionTargetOrPanelTypes() throws {
        let forbidden = try Self.declaredTypeNames(inFolder: Self.insertionTargetFolder, includingSubfolders: false)
            .union(try Self.declaredTypeNames(inFolder: Self.panelFolder, includingSubfolders: true))
        for expected in ["InsertionTargetMonitor", "PanelModel", "CommitPerformer"] {
            #expect(forbidden.contains(expected), "\(expected) が禁止の名前の集合に入っていません")
        }

        let used = try Self.usedNames(inFolder: Self.insertionFolder, from: forbidden)
        #expect(used.isEmpty, "Insertion/ が InsertionTarget/・Panel/ の型を使っています: \(used)")
    }

    @Test("AC-2: InsertionTarget/ のファイルは、Insertion/ と AutoShow/ で宣言された型を使わない")
    func insertionTargetDoesNotUseInsertionOrAutoShowTypes() throws {
        let forbidden = try Self.declaredTypeNames(inFolder: Self.insertionFolder, includingSubfolders: false)
            .union(try Self.declaredTypeNames(inFolder: Self.autoShowFolder, includingSubfolders: false))
        for expected in ["ClipboardTextInserter", "AutoShowDecision"] {
            #expect(forbidden.contains(expected), "\(expected) が禁止の名前の集合に入っていません")
        }

        let used = try Self.usedNames(inFolder: Self.insertionTargetFolder, from: forbidden)
        #expect(used.isEmpty, "InsertionTarget/ が Insertion/・AutoShow/ の型を使っています: \(used)")
    }
}
