import Foundation
import Testing

private let fakeSignUpdateScript = """
#!/bin/bash
echo "sign_update $*" >> "$FAKE_LOG"
target=""
for arg in "$@"; do
  case "$arg" in
    *.dmg|*.xml) target="$arg" ;;
  esac
done
case " $* " in
  *" --ed-key-file - "*) cat > /dev/null ;;
esac
case "$target" in
  *.dmg)
    if [ "${FAKE_SIGN_DMG:-ok}" = fail ]; then
      exit 1
    fi
    echo 'sparkle:edSignature="FAKEDMGSIGNATURE==" length="1234"'
    ;;
  *.xml)
    case "${FAKE_SIGN_APPCAST:-append}" in
      append)
        {
          echo '<!-- sparkle-signatures:'
          echo 'edSignature: FAKEAPPCASTSIGNATURE=='
          echo '-->'
        } >> "$target"
        ;;
      none) ;;
      fail) exit 1 ;;
    esac
    ;;
esac
exit 0
"""

private let fakeGhScript = """
#!/bin/bash
echo "gh $*" >> "$FAKE_LOG"
if [ "$1 $2" = "release view" ]; then
  echo "release not found" >&2
  exit 1
fi
exit 0
"""

private let fakeXcrunScript = """
#!/bin/bash
exit 0
"""

private struct ReleaseSandbox {
    let directory: URL

    var appcast: URL { directory.appendingPathComponent("dist/appcast.xml") }
    var log: URL { directory.appendingPathComponent("calls.log") }

    static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    init(withSignUpdate: Bool = true, withFakeGhAndXcrun: Bool = false) throws {
        let fileManager = FileManager.default
        directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let scripts = directory.appendingPathComponent("scripts")
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        for name in ["release.sh", "release.conf"] {
            try fileManager.copyItem(
                at: Self.appRoot.appendingPathComponent("scripts/\(name)"),
                to: scripts.appendingPathComponent(name)
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scripts.appendingPathComponent("release.sh").path
        )

        try "1.2.3\n".write(to: directory.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        let notes = directory.appendingPathComponent("release-notes")
        try fileManager.createDirectory(at: notes, withIntermediateDirectories: true)
        try "## 変更点\n- 見本の変更\n".write(
            to: notes.appendingPathComponent("v1.2.3.md"),
            atomically: true,
            encoding: .utf8
        )

        let dist = directory.appendingPathComponent("dist")
        try fileManager.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1234).write(to: dist.appendingPathComponent("TatakiNote-1.2.3.dmg"))

        if withSignUpdate {
            let bin = directory.appendingPathComponent(".build/release/SourcePackages/artifacts/sparkle/Sparkle/bin")
            try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
            try Self.writeExecutable(fakeSignUpdateScript, to: bin.appendingPathComponent("sign_update"))
        }

        let fakebin = directory.appendingPathComponent("fakebin")
        try fileManager.createDirectory(at: fakebin, withIntermediateDirectories: true)
        if withFakeGhAndXcrun {
            try Self.writeExecutable(fakeGhScript, to: fakebin.appendingPathComponent("gh"))
            try Self.writeExecutable(fakeXcrunScript, to: fakebin.appendingPathComponent("xcrun"))
        }
    }

    func placeOldAppcast() throws {
        try "old".write(to: appcast, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func run(
        _ arguments: [String],
        signDMG: String = "ok",
        signAppcast: String = "append"
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [directory.appendingPathComponent("scripts/release.sh").path] + arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": "\(directory.path)/fakebin:/usr/bin:/bin",
            "HOME": directory.path,
            "SPARKLE_ED_PRIVATE_KEY": "dummy",
            "FAKE_LOG": log.path,
            "FAKE_SIGN_DMG": signDMG,
            "FAKE_SIGN_APPCAST": signAppcast,
            "GITHUB_SHA": "0000000000000000000000000000000000000000",
            "GH_REPO": "tk-niway/tataki-note",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func writeExecutable(_ script: String, to url: URL) throws {
        try (script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

struct ReleaseAppcastSigningTests {
    private func logText(_ sandbox: ReleaseSandbox) -> String {
        (try? String(contentsOf: sandbox.log, encoding: .utf8)) ?? ""
    }

    @Test("AC-1: appcast は末尾に署名のコメントが入り、ほかの中身は今のまま")
    func appcastIsSigned() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }

        let result = try sandbox.run(["appcast"])
        #expect(result.status == 0, "終了コード: \(result.status) 出力: \(result.output)")

        let text = try String(contentsOf: sandbox.appcast, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let signatureStart = try #require(lines.firstIndex { $0.contains("<!-- sparkle-signatures:") })
        let signatureLine = try #require(lines.firstIndex { $0.contains("edSignature:") })
        #expect(signatureStart < signatureLine)
        let lastNonEmpty = try #require(lines.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(signatureLine <= lastNonEmpty)
        #expect(lines[lastNonEmpty].trimmingCharacters(in: .whitespaces) == "-->")

        let body = lines[..<signatureStart].joined(separator: "\n")
        #expect(body.contains("<sparkle:version>1.2.3</sparkle:version>"))
        #expect(body.contains("<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"))
        #expect(body.contains("releases/download/v1.2.3/TatakiNote-1.2.3.dmg"))
        #expect(body.contains("length=\"1234\""))
        #expect(body.contains("sparkle:edSignature=\"FAKEDMGSIGNATURE==\""))
        #expect(body.contains("<li>見本の変更</li>"))
    }

    @Test("AC-1: 前の実行の appcast.xml の中身は残らない")
    func previousAppcastIsReplaced() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast"])
        #expect(result.status == 0, "終了コード: \(result.status) 出力: \(result.output)")

        let text = try String(contentsOf: sandbox.appcast, encoding: .utf8)
        #expect(!text.contains("old"))
        #expect(text.contains("<rss"))
    }

    @Test("AC-1: --dry-run は署名せず、ファイルを書かず・消さずに標準出力へ出す")
    func dryRunDoesNotSign() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast", "--dry-run"])
        #expect(result.status == 0, "終了コード: \(result.status) 出力: \(result.output)")
        #expect(result.output.contains("<rss"))
        #expect(!result.output.contains("sparkle-signatures"))
        #expect(!result.output.contains("sparkle:edSignature"))
        #expect(logText(sandbox).isEmpty)
        #expect(try String(contentsOf: sandbox.appcast, encoding: .utf8) == "old")
    }

    @Test("AC-2: DMG の署名に失敗すると止まり、appcast.xml を残さない")
    func dmgSigningFailureStops() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast"], signDMG: "fail")
        #expect(result.status != 0)
        #expect(result.output.contains("DMG に署名できませんでした"), "出力: \(result.output)")
        #expect(!FileManager.default.fileExists(atPath: sandbox.appcast.path))
    }

    @Test("AC-2: sign_update が無いと止まり、appcast.xml を残さない")
    func missingSignUpdateStops() throws {
        let sandbox = try ReleaseSandbox(withSignUpdate: false)
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast"])
        #expect(result.status != 0)
        #expect(result.output.contains("sign_update がありません"), "出力: \(result.output)")
        #expect(!result.output.contains("署名できませんでした"), "出力: \(result.output)")
        #expect(!result.output.contains("署名を読めませんでした"), "出力: \(result.output)")
        #expect(!FileManager.default.fileExists(atPath: sandbox.appcast.path))
    }

    @Test("AC-2: appcast の署名で sign_update が失敗すると止まり、appcast.xml を残さない")
    func appcastSigningFailureStops() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast"], signAppcast: "fail")
        #expect(result.status != 0)
        #expect(result.output.contains("appcast.xml に署名できませんでした"), "出力: \(result.output)")
        #expect(!FileManager.default.fileExists(atPath: sandbox.appcast.path))
    }

    @Test("AC-2: 署名の後のファイルに署名のコメントが無いと止まり、appcast.xml を残さない")
    func missingSignatureCommentStops() throws {
        let sandbox = try ReleaseSandbox()
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["appcast"], signAppcast: "none")
        #expect(result.status != 0)
        #expect(result.output.contains("appcast.xml に署名が入っていません"), "出力: \(result.output)")
        #expect(!FileManager.default.fileExists(atPath: sandbox.appcast.path))
    }

    @Test("AC-2: 署名に失敗した upload は gh でリリースを作らず・更新せず・添付しない")
    func uploadStopsBeforeReleasing() throws {
        let sandbox = try ReleaseSandbox(withFakeGhAndXcrun: true)
        defer { sandbox.remove() }
        try sandbox.placeOldAppcast()

        let result = try sandbox.run(["upload"], signAppcast: "fail")
        #expect(result.status != 0, "出力: \(result.output)")
        let log = logText(sandbox)
        #expect(log.contains("release view"), "ログ: \(log)")
        #expect(!log.contains("release create"))
        #expect(!log.contains("release edit"))
        #expect(!log.contains("release upload"))
        #expect(!FileManager.default.fileExists(atPath: sandbox.appcast.path))
    }
}
