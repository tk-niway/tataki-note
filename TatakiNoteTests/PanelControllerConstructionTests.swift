import Foundation
import Testing

struct PanelControllerConstructionTests {
    private static let factoryFile = "TestDoubles/PanelControllerFactory.swift"
    private static let constructionPattern = "(?<![A-Za-z])" + "PanelController" + "\\("

    @Test("AC-1: 単体テストのファイルのうち、PanelController を作る式を含むのは TestDoubles/PanelControllerFactory.swift だけ")
    func onlyFactoryConstructsPanelController() throws {
        let expression = try NSRegularExpression(pattern: Self.constructionPattern)
        let files = try TestSourceFiles.swiftFiles(in: TestSourceFiles.testsDirectory)
        #expect(!files.isEmpty, "\(TestSourceFiles.testsDirectory.path) にテストのファイルがありません")

        var constructing: [String] = []
        for file in files {
            let source = try String(contentsOf: TestSourceFiles.testsDirectory.appendingPathComponent(file), encoding: .utf8)
            let hasConstruction = source.components(separatedBy: .newlines).contains { line in
                expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
            }
            if hasConstruction {
                constructing.append(file)
            }
        }
        #expect(constructing == [Self.factoryFile], "PanelController を直接作っているテスト: \(constructing.joined(separator: ", "))")
    }
}
