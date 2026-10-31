import Foundation
import Testing

struct ReleaseHardeningTests {
    private static let rootDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var workflowsDirectory: URL {
        rootDirectory.appendingPathComponent(".github/workflows")
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func workflowFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: Self.workflowsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func lines(of url: URL) throws -> [String] {
        try read(url).components(separatedBy: "\n")
    }

    private func isUsesLine(_ line: String) -> Bool {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            trimmed = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed.hasPrefix("uses:")
    }

    private func stepName(endingAt tokenIndex: Int, in lines: [String]) -> String? {
        var start = tokenIndex
        while start >= 0, !lines[start].hasPrefix("      - ") {
            if lines[start].range(of: #"^  [A-Za-z_-]+:\s*$"#, options: .regularExpression) != nil
                || lines[start] == "    env:" {
                return nil
            }
            start -= 1
        }
        guard start >= 0 else { return nil }
        for index in start...tokenIndex {
            var text = lines[index].trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("- ") {
                text = String(text.dropFirst(2))
            }
            if text.hasPrefix("name:") {
                return text.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    @Test("AC-3: Info.plist が署名された appcast を求め、ほかの更新の設定は今のまま")
    func infoPlistRequiresSignedFeed() throws {
        let url = Self.rootDirectory.appendingPathComponent("TatakiNote/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["SURequireSignedFeed"] as? Bool == true, "SURequireSignedFeed が true ではありません: \(url.path)")
        #expect(plist["SUPublicEDKey"] as? String == "8EJ1qId/xq8WX0lkZmcqWmpiQm3SaoVZ3GNM0i+X7UA=")
        #expect(
            plist["SUFeedURL"] as? String
                == "https://github.com/tk-niway/tataki-note/releases/latest/download/appcast.xml"
        )
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
    }

    @Test("AC-6: ワークフローの外部のアクションはすべてコミットの SHA で固定されている")
    func actionsArePinnedToCommitSHA() throws {
        let files = try workflowFiles()
        #expect(files.count >= 3, "ワークフローのファイルが3つ未満です: \(files.count)")
        let pattern = #"^\s*(-\s+)?uses:\s*[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}(\s+#.*)?$"#
        var usesCount = 0
        for file in files {
            for (index, line) in try lines(of: file).enumerated() where isUsesLine(line) {
                usesCount += 1
                #expect(
                    line.range(of: pattern, options: .regularExpression) != nil,
                    "SHA で固定されていません: \(file.lastPathComponent):\(index + 1): \(line)"
                )
            }
        }
        #expect(usesCount >= 1, "uses: の行が見つかりません")
    }

    @Test("AC-6: actions/checkout はすべて persist-credentials: false")
    func checkoutDoesNotPersistCredentials() throws {
        for file in try workflowFiles() {
            let all = try lines(of: file)
            let checkouts = all.filter { $0.contains("actions/checkout@") }.count
            let disabled = all.filter {
                $0.trimmingCharacters(in: .whitespaces) == "persist-credentials: false"
            }.count
            #expect(
                checkouts == disabled,
                "checkout \(checkouts) 個に対し persist-credentials: false が \(disabled) 個です: \(file.lastPathComponent)"
            )
        }
    }

    @Test("AC-6: release.yml の権限は contents: read が既定で、contents: write は release ジョブだけ")
    func releaseWorkflowPermissionsAreMinimal() throws {
        let file = Self.workflowsDirectory.appendingPathComponent("release.yml")
        let all = try lines(of: file)
        let topLevel = try #require(all.firstIndex(of: "permissions:"), "最上位の permissions: がありません")
        #expect(
            all.indices.contains(topLevel + 1) && all[topLevel + 1] == "  contents: read",
            "最上位の permissions の次の行が contents: read ではありません: release.yml:\(topLevel + 2)"
        )
        let writes = all.enumerated().filter { $0.element.contains("contents: write") }
        #expect(writes.count == 1, "contents: write が \(writes.count) 個です")
        let releaseJob = try #require(all.firstIndex(of: "  release:"), "release ジョブがありません")
        if let write = writes.first {
            #expect(write.offset > releaseJob, "contents: write が release ジョブの外にあります: release.yml:\(write.offset + 1)")
        }
    }

    @Test("AC-6: release.yml の GH_TOKEN は Check whether to release と Publish release の手順だけ")
    func tokenIsOnlyInTwoSteps() throws {
        let file = Self.workflowsDirectory.appendingPathComponent("release.yml")
        let all = try lines(of: file)
        let tokenLines = all.enumerated().filter { $0.element.contains("GH_TOKEN:") }
        #expect(tokenLines.count == 2, "GH_TOKEN: が \(tokenLines.count) 個です")
        var names: [String] = []
        for (index, _) in tokenLines {
            let name = stepName(endingAt: index, in: all)
            #expect(name != nil, "手順の env の外に GH_TOKEN があります: release.yml:\(index + 1)")
            names.append(name ?? "")
        }
        #expect(names == ["Check whether to release", "Publish release"], "GH_TOKEN を持つ手順: \(names)")
        let githubTokenLines = all.enumerated().filter { $0.element.contains("github.token") }
        #expect(
            githubTokenLines.map(\.offset) == tokenLines.map(\.offset),
            "github.token が GH_TOKEN 以外の行にもあります: \(githubTokenLines.map { $0.offset + 1 })"
        )
    }

    @Test("AC-7: release.sh の xcodebuild の build と test は Package.resolved の版だけを使う")
    func xcodebuildUsesResolvedVersionsOnly() throws {
        let file = Self.rootDirectory.appendingPathComponent("scripts/release.sh")
        let all = try lines(of: file)
        var invocations: [(line: Int, text: String)] = []
        var index = 0
        while index < all.count {
            let trimmed = all[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("xcodebuild build") || trimmed.hasPrefix("xcodebuild test") else {
                index += 1
                continue
            }
            var text = all[index]
            var end = index
            while all[end].hasSuffix("\\"), end + 1 < all.count {
                end += 1
                text += "\n" + all[end]
            }
            invocations.append((index + 1, text))
            index = end + 1
        }
        #expect(invocations.count >= 2, "xcodebuild の build・test の呼び出しが \(invocations.count) 個です")
        for invocation in invocations {
            #expect(
                invocation.text.contains("-onlyUsePackageVersionsFromResolvedFile"),
                "-onlyUsePackageVersionsFromResolvedFile がありません: release.sh:\(invocation.line)"
            )
        }
    }
}
