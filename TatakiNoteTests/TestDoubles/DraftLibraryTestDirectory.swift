import Foundation
import Testing
@testable import TatakiNote

/// テストごとの一時ディレクトリ。
final class DraftLibraryTestDirectory {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TatakiNoteTests-\(UUID().uuidString)", isDirectory: true)
    }

    var dataDirectory: URL { root.appendingPathComponent("data", isDirectory: true) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path)) ?? []).sorted()
    }

    func write(_ contents: String, named fileName: String) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dataDirectory.appendingPathComponent(fileName))
    }

    func read(_ fileName: String) -> String? {
        (try? Data(contentsOf: dataDirectory.appendingPathComponent(fileName))).flatMap { String(data: $0, encoding: .utf8) }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
