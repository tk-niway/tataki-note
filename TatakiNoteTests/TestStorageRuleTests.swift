import Foundation
import Testing

struct TestStorageRuleTests {
    private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let sharedStoragePatterns = [
        "UserDefaults" + "(suiteName",
        "UserDefaults" + "()",
        "UserDefaults" + ".standard.set",
        "UserDefaults" + ".standard.removeObject",
        "NSPasteboard" + ".general.clearContents",
        "NSPasteboard" + ".general.set",
        "NSPasteboard" + ".general.write",
    ]

    @Test("単体テストは Mac で共有する保存先(本物の UserDefaults・共有のクリップボード)に書かない")
    func unitTestsDoNotWriteSharedStorage() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.testsDirectory.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty, "\(Self.testsDirectory.path) にテストのファイルがありません")

        var offenders: [String] = []
        for file in files.sorted() {
            let source = try String(contentsOf: Self.testsDirectory.appendingPathComponent(file), encoding: .utf8)
            for pattern in Self.sharedStoragePatterns where source.contains(pattern) {
                offenders.append("\(file): \(pattern)")
            }
        }
        #expect(offenders.isEmpty, "Mac で共有する保存先を使っています(設定は InMemoryDefaults を使ってください): \(offenders.joined(separator: ", "))")
    }
}
