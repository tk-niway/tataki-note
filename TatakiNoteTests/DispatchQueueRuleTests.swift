import Foundation
import Testing

struct DispatchQueueRuleTests {
    private static let allowedFiles: Set<String> = [
        "Drafts/DraftLibraryWriter.swift",
        "Updates/NetworkPathMonitor.swift",
    ]

    private static func files(containing text: String) throws -> (scanned: Int, matches: Set<String>) {
        let files = try TestSourceFiles.swiftFiles(in: TestSourceFiles.appSourceDirectory)
        var matches: Set<String> = []
        for file in files {
            let url = TestSourceFiles.appSourceDirectory.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains(text) {
                matches.insert(file)
            }
        }
        return (files.count, matches)
    }

    @Test("AC-7: アプリのソースで DispatchQueue を使うファイルは、つなぎ目の NetworkPathMonitor と DraftLibraryWriter だけ")
    func dispatchQueueIsUsedOnlyAtSeams() throws {
        let result = try Self.files(containing: "DispatchQueue")

        #expect(result.scanned > 0)
        #expect(
            result.matches == Self.allowedFiles,
            "DispatchQueue を使っているファイル: \(result.matches.sorted().joined(separator: ", "))"
        )
    }

    @Test("AC-7: DispatchQueue.main はどのファイルにも無い")
    func dispatchQueueMainIsNotUsed() throws {
        let result = try Self.files(containing: "DispatchQueue.main")

        #expect(result.scanned > 0)
        #expect(
            result.matches.isEmpty,
            "DispatchQueue.main を使っているファイル: \(result.matches.sorted().joined(separator: ", "))"
        )
    }
}
