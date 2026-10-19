import Foundation
import Testing

struct TestStorageRuleTests {
    private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let realDefaultsFiles: Set<String> = ["RealUserDefaultsTests.swift"]
    private static let realSuitePattern = "UserDefaults" + "(suiteName"

    @Test("単体テストで本物の UserDefaults の suite を作るのは RealUserDefaultsTests だけ")
    func realSuitesOnlyInRealUserDefaultsTests() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.testsDirectory.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(!files.isEmpty, "\(Self.testsDirectory.path) にテストのファイルがありません")

        var offenders: [String] = []
        for file in files.sorted() where !Self.realDefaultsFiles.contains(file) {
            let source = try String(contentsOf: Self.testsDirectory.appendingPathComponent(file), encoding: .utf8)
            if source.contains(Self.realSuitePattern) {
                offenders.append(file)
            }
        }
        #expect(offenders.isEmpty, "本物の UserDefaults の suite を作っています(InMemoryDefaults を使ってください): \(offenders.joined(separator: ", "))")
    }
}
