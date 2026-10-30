import Foundation
import Testing

private struct CheckResult {
    let status: Int32
    let output: String
}

private struct CheckSandbox {
    let directory: URL
    let repo: URL
    let scratch: URL

    static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    init() throws {
        let fileManager = FileManager.default
        directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        repo = directory.appendingPathComponent("repo")
        scratch = directory.appendingPathComponent("scratch")
        let scripts = repo.appendingPathComponent("scripts")
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: Self.appRoot.appendingPathComponent("scripts/check-public.sh"),
            to: scripts.appendingPathComponent("check-public.sh")
        )
        _ = try git(["init", "-q"])
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func environment(home: URL, scratch: URL) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin",
            "HOME": home.path,
            "TMPDIR": scratch.path,
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        ]
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL,
        home: URL,
        scratch: URL
    ) throws -> CheckResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment(home: home, scratch: scratch)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CheckResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> CheckResult {
        let base = [
            "-c", "core.hooksPath=/dev/null",
            "-c", "user.name=test",
            "-c", "user.email=test@example.com",
            "-c", "commit.gpgsign=false",
        ]
        return try Self.run("/usr/bin/git", base + arguments, in: repo, home: directory, scratch: scratch)
    }

    func write(_ relativePath: String, _ text: String) throws {
        try write(relativePath, Data(text.utf8))
    }

    func write(_ relativePath: String, _ data: Data) throws {
        let url = repo.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func check(_ arguments: [String]) throws -> CheckResult {
        try Self.run(
            "/bin/bash",
            [repo.appendingPathComponent("scripts/check-public.sh").path] + arguments,
            in: repo,
            home: directory,
            scratch: scratch
        )
    }

    func checkAll(adding relativePath: String, _ text: String) throws -> CheckResult {
        try write(relativePath, text)
        try git(["add", "-A"])
        return try check(["--all"])
    }

    func checkStaged(adding relativePath: String, _ text: String) throws -> CheckResult {
        try write(relativePath, text)
        try git(["add", "-A"])
        return try check(["--staged"])
    }

    func commitBase() throws -> String {
        try write("base.txt", "base\n")
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "base"])
        return try git(["rev-parse", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shortHash() throws -> String {
        try git(["rev-parse", "--short", "HEAD"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private nonisolated enum Sample {
    static let githubToken = "gh" + "p_" + String(repeating: "A", count: 36)
    static let rsaPrivateKeyHeader = "-----BEGIN " + "RSA PRIVATE KEY-----"

    static func repeated(_ character: String, _ count: Int) -> String {
        String(repeating: character, count: count)
    }

    static let secretLines: [(String, String)] = {
        let github = "GitHub のトークン"
        let asana = "ASANA_" + "TOKEN="
        let sparkle = "SPARKLE_ED_" + "PRIVATE_KEY="
        var lines: [(String, String)] = []
        lines.append(("gh" + "p_" + repeated("A", 36), github))
        lines.append(("gh" + "o_" + repeated("B", 36), github))
        lines.append(("gh" + "u_" + repeated("C", 40), github))
        lines.append(("gh" + "s_" + repeated("D", 36), github))
        lines.append(("gh" + "r_" + repeated("E", 36), github))
        lines.append(("github" + "_pat_" + repeated("F", 22), github))
        lines.append(("sk-" + "ant-" + repeated("g", 20), "Anthropic の API キー"))
        lines.append((asana + "1/1234567890123:abcdef", "ASANA_TOKEN の値"))
        lines.append((sparkle + repeated("A", 44), "SPARKLE_ED_PRIVATE_KEY の値"))
        return lines
    }()

    static let harmlessLines: [String] = {
        let asana = "ASANA_" + "TOKEN="
        let sparkle = "SPARKLE_ED_" + "PRIVATE_KEY"
        var lines: [String] = []
        lines.append(asana)
        lines.append(asana + "\"${ASANA_" + "TOKEN}\"")
        lines.append(asana + "<token>")
        lines.append(asana + "xxxx")
        lines.append("gh" + "p_abc")
        lines.append("x" + "gh" + "p_" + repeated("A", 36))
        lines.append("sk-" + "ant-")
        lines.append("sk-" + "ant-xxx")
        lines.append(sparkle + ": ${{ secrets." + sparkle + " }}")
        return lines
    }()

    static func privateKeyHeader(_ kind: String) -> String {
        let separator: String = kind.isEmpty ? "" : " "
        let head: String = "-----BEGIN " + kind + separator
        return head + "PRIVATE " + "KEY-----"
    }

    static func publicHeader(_ kind: String) -> String {
        "-----BEGIN " + kind + "-----"
    }
}

struct PublicCheckSecretsTests {
    @Test("AC-9: 秘密鍵の頭書きがあると --all で止まる", arguments: ["RSA", "EC", "OPENSSH", "ENCRYPTED", ""])
    func privateKeyHeaderStopsAll(kind: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(
            adding: "notes.txt",
            Sample.privateKeyHeader(kind) + "\nAAAA\n"
        )
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("notes.txt:1: 秘密情報(秘密鍵)が書かれています"), "出力: \(result.output)")
    }

    @Test("AC-9: 秘密鍵の頭書きがあると --staged で止まる", arguments: ["RSA", "EC", "OPENSSH", "ENCRYPTED", ""])
    func privateKeyHeaderStopsStaged(kind: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkStaged(
            adding: "notes.txt",
            "memo\n" + Sample.privateKeyHeader(kind) + "\n"
        )
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("notes.txt:2: 秘密情報(秘密鍵)が書かれています"), "出力: \(result.output)")
    }

    @Test("AC-9: 公開鍵と証明書の頭書きは通る", arguments: ["PUBLIC KEY", "CERTIFICATE"])
    func publicHeaderPasses(kind: String) throws {
        let allSandbox = try CheckSandbox()
        defer { allSandbox.remove() }
        let all = try allSandbox.checkAll(adding: "notes.txt", Sample.publicHeader(kind) + "\nAAAA\n")
        #expect(all.status == 0, "出力: \(all.output)")

        let stagedSandbox = try CheckSandbox()
        defer { stagedSandbox.remove() }
        let staged = try stagedSandbox.checkStaged(adding: "notes.txt", Sample.publicHeader(kind) + "\nAAAA\n")
        #expect(staged.status == 0, "出力: \(staged.output)")
    }

    @Test("AC-10: トークン・API キー・値の入った設定は止まる", arguments: Sample.secretLines)
    func tokenStops(line: String, label: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: "notes.md", "token は次\n" + line + "\n")
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("notes.md:2: 秘密情報(\(label))が書かれています"), "出力: \(result.output)")
    }

    @Test("AC-10: 値の無いもの・短いもの・変数の参照は通る", arguments: Sample.harmlessLines)
    func nonSecretPasses(line: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: "notes.md", line + "\n")
        #expect(result.status == 0, "出力: \(result.output)")
    }

    @Test(
        "AC-11: 鍵・証明書の拡張子のファイルは止まる",
        arguments: [
            "certs/dev.pem",
            "server.key",
            "cert.p12",
            "cert.pfx",
            "AuthKey.p8",
            "AuthKey.P8",
            "Dev.PEM",
            "login.keychain",
            "signing.keychain-db",
        ]
    )
    func secretFileNameStops(path: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: path, "memo\n")
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("\(path): 秘密鍵・証明書のファイルは置きません"), "出力: \(result.output)")
    }

    @Test("AC-11: バイナリの鍵のファイルも名前で止まり、中身は見ない")
    func binarySecretFileStopsByName() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        var binary = Data([0x00, 0xFF, 0x01])
        binary.append(Data(Sample.rsaPrivateKeyHeader.utf8))
        binary.append(0x00)
        try sandbox.write("cert.p12", binary)
        try sandbox.git(["add", "-A"])
        for mode in ["--all", "--staged"] {
            let result = try sandbox.check([mode])
            #expect(result.status == 1, "\(mode) 出力: \(result.output)")
            #expect(result.output.contains("cert.p12: 秘密鍵・証明書のファイルは置きません"), "\(mode) 出力: \(result.output)")
            #expect(!result.output.contains("秘密情報("), "\(mode) 出力: \(result.output)")
        }
    }

    @Test(
        "AC-11: 拡張子ではない名前は通る",
        arguments: ["App/key.swift", "p8-notes.md", "keys.md", "Keyboard.key.md"]
    )
    func similarNamePasses(path: String) throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let body = path.hasSuffix(".swift") ? "struct K {}\n" : "memo\n"
        let result = try sandbox.checkAll(adding: path, body)
        #expect(result.status == 0, "出力: \(result.output)")
    }

    @Test("AC-12: ファイルの本文のトークンは、場所と種類だけを出して値を出さない")
    func fileContentReportHidesValue() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: "notes.md", Sample.githubToken + "\n")
        #expect(result.status == 1)
        #expect(result.output.contains("notes.md:1: 秘密情報(GitHub のトークン)が書かれています"), "出力: \(result.output)")
        #expect(!result.output.contains(Sample.githubToken), "出力: \(result.output)")
    }

    @Test("AC-12: --message のトークンは、場所と種類だけを出して値を出さない")
    func messageReportHidesValue() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.check(["--message", Sample.githubToken])
        #expect(result.status == 1)
        #expect(result.output.contains("メッセージ:1: 秘密情報(GitHub のトークン)"), "出力: \(result.output)")
        #expect(!result.output.contains(Sample.githubToken), "出力: \(result.output)")
    }

    @Test("AC-12: --range の場所はコミットの短いハッシュだけで、件名もトークンも出さない")
    func rangeReportHidesSubjectAndValue() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let base = try sandbox.commitBase()
        try sandbox.git(["commit", "-q", "--allow-empty", "-m", "secret-subject " + Sample.githubToken])
        let hash = try sandbox.shortHash()

        let result = try sandbox.check(["--range", "\(base)..HEAD"])
        #expect(result.status == 1)
        #expect(
            result.output.contains("コミット \(hash):1: 秘密情報(GitHub のトークン)が書かれています"),
            "出力: \(result.output)"
        )
        #expect(!result.output.contains(Sample.githubToken), "出力: \(result.output)")
        #expect(!result.output.contains("secret-subject"), "出力: \(result.output)")
    }

    @Test("AC-12: 鍵のファイルの問題は、ファイル名だけを出して中身の値を出さない")
    func secretFileReportHidesValue() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: "AuthKey.p8", Sample.githubToken + "\n")
        #expect(result.status == 1)
        #expect(result.output.contains("AuthKey.p8: 秘密鍵・証明書のファイルは置きません"), "出力: \(result.output)")
        #expect(!result.output.contains(Sample.githubToken), "出力: \(result.output)")
    }

    @Test("AC-12: 手元のパスの問題の行は今の文言のまま")
    func localPathReportKeepsWording() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.checkAll(adding: "notes.md", "see " + "ai-" + "pipeline/x\n")
        #expect(result.status == 1)
        #expect(result.output.contains("notes.md:1: 手元の作業場所のパスが書かれています: see "), "出力: \(result.output)")
    }

    @Test("AC-13: --message の秘密鍵の頭書きで止まる")
    func messageWithPrivateKeyHeaderStops() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.check(["--message", "subject\n" + Sample.rsaPrivateKeyHeader])
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("メッセージ:2: 秘密情報(秘密鍵)"), "出力: \(result.output)")
    }

    @Test("AC-13: --message-file の2行目のトークンで止まり、# の行は見ない")
    func messageFileWithTokenStops() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let stopping = sandbox.scratch.appendingPathComponent("stopping-message")
        try "subject\n\(Sample.githubToken)\n# comment\n".write(to: stopping, atomically: true, encoding: .utf8)
        let result = try sandbox.check(["--message-file", stopping.path])
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("コミットメッセージ:2: 秘密情報(GitHub のトークン)"), "出力: \(result.output)")

        let commented = sandbox.scratch.appendingPathComponent("commented-message")
        try "subject\n# \(Sample.githubToken)\n".write(to: commented, atomically: true, encoding: .utf8)
        let passing = try sandbox.check(["--message-file", commented.path])
        #expect(passing.status == 0, "出力: \(passing.output)")
    }

    @Test("AC-13: --range のコミットの本文のトークンで止まる")
    func rangeWithTokenInBodyStops() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let base = try sandbox.commitBase()
        try sandbox.git([
            "commit", "-q", "--allow-empty",
            "-m", "subject",
            "-m", "first line\n" + Sample.githubToken,
        ])
        let hash = try sandbox.shortHash()

        let result = try sandbox.check(["--range", "\(base)..HEAD"])
        #expect(result.status == 1, "出力: \(result.output)")
        #expect(result.output.contains("コミット \(hash):4: 秘密情報(GitHub のトークン)"), "出力: \(result.output)")
    }

    @Test("AC-14: 今ある自己テストがすべて通る")
    func existingSelfTestPasses() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try CheckSandbox.run(
            "/bin/bash",
            [CheckSandbox.appRoot.appendingPathComponent("scripts/test-check-public.sh").path],
            in: CheckSandbox.appRoot,
            home: sandbox.directory,
            scratch: sandbox.scratch
        )
        #expect(result.status == 0, "出力: \(result.output)")
    }

    @Test("AC-14: 今のリポジトリの追跡しているファイルが --all で通る")
    func currentRepositoryPassesAll() throws {
        let sandbox = try CheckSandbox()
        defer { sandbox.remove() }

        let result = try CheckSandbox.run(
            "/bin/bash",
            [CheckSandbox.appRoot.appendingPathComponent("scripts/check-public.sh").path, "--all"],
            in: CheckSandbox.appRoot,
            home: sandbox.directory,
            scratch: sandbox.scratch
        )
        #expect(result.status == 0, "出力: \(result.output)")
    }
}
