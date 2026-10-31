import Foundation

/// テストから読むリポジトリの中の場所と、Swift のファイルの一覧。
enum TestSourceFiles {
    /// 単体テストのフォルダ(`TatakiNoteTests/`)。
    static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// アプリのリポジトリの直下(`CLAUDE.md` があるところ)。
    static let repositoryRoot = testsDirectory.deletingLastPathComponent()

    /// アプリのソースのフォルダ(`TatakiNote/`)。
    static let appSourceDirectory = repositoryRoot.appendingPathComponent("TatakiNote", isDirectory: true)

    /// フォルダの下の .swift の、フォルダからの相対パス(サブフォルダも含む。並びは名前順)。
    static func swiftFiles(in directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return enumerator
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }
}
