import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct ApplicationMoverTests {
    private static let quarantine = "com.apple.quarantine"

    private struct Sandbox {
        let root: URL
        let source: URL
        let destination: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            source = root.appendingPathComponent("src/TatakiNote.app", isDirectory: true)
            destination = root.appendingPathComponent("dest", isDirectory: true)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: source.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try "new".write(to: source.appendingPathComponent("Contents/payload.txt"), atomically: true, encoding: .utf8)
            try Self.setQuarantine(source.path)
            try Self.setQuarantine(source.appendingPathComponent("Contents/payload.txt").path)
        }

        var target: URL { destination.appendingPathComponent("TatakiNote.app", isDirectory: true) }

        func makeExistingTarget() throws {
            let contents = target.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try "old".write(to: contents.appendingPathComponent("payload.txt"), atomically: true, encoding: .utf8)
            try "old-only".write(to: contents.appendingPathComponent("old-only.txt"), atomically: true, encoding: .utf8)
        }

        func payload(of app: URL) -> String? {
            try? String(contentsOf: app.appendingPathComponent("Contents/payload.txt"), encoding: .utf8)
        }

        func destinationEntries() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            try? FileManager.default.removeItem(at: root)
        }

        private static func setQuarantine(_ path: String) throws {
            let value = Array("0081;00000000;Safari;".utf8)
            guard setxattr(path, ApplicationMoverTests.quarantine, value, value.count, 0, 0) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    private func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, Self.quarantine, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    private func makeMover(
        sandbox: Sandbox,
        copy: @escaping (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        discard: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        replace: @escaping (URL, URL) throws -> Void = { _ = try FileManager.default.replaceItemAt($0, withItemAt: $1) }
    ) -> ApplicationMover {
        ApplicationMover(destinationDirectory: sandbox.destination, copy: copy, discard: discard, replace: replace)
    }

    private struct InjectedFailure: Error {}

    // MARK: - 移動

    @Test("AC-19: 移す先が空なら、TatakiNote が置かれ、隔離の印は中のファイルまで外れ、元はダウンロードなら消える")
    func movesIntoEmptyDestinationAndRemovesSource() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let result = try makeMover(sandbox: sandbox).move(from: sandbox.source, as: .removable)

        #expect(result.standardizedFileURL == sandbox.target.standardizedFileURL)
        #expect(sandbox.payload(of: sandbox.target) == "new")
        #expect(!hasQuarantine(sandbox.target))
        #expect(!hasQuarantine(sandbox.target.appendingPathComponent("Contents/payload.txt")))
        #expect(!FileManager.default.fileExists(atPath: sandbox.source.path))
        #expect(try sandbox.destinationEntries() == ["TatakiNote.app"])
    }

    @Test("AC-19: 元が DMG・隔離された場所なら、元を残して写す")
    func readOnlySourceIsKept() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        _ = try makeMover(sandbox: sandbox).move(from: sandbox.source, as: .readOnly)

        #expect(sandbox.payload(of: sandbox.target) == "new")
        #expect(sandbox.payload(of: sandbox.source) == "new")
        #expect(hasQuarantine(sandbox.source))
    }

    @Test("AC-19: 同じ名前があれば、新しい中身に置き換わり、古い中身は残らない")
    func replacesExistingApplication() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeExistingTarget()

        _ = try makeMover(sandbox: sandbox).move(from: sandbox.source, as: .removable)

        #expect(sandbox.payload(of: sandbox.target) == "new")
        #expect(!FileManager.default.fileExists(atPath: sandbox.target.appendingPathComponent("Contents/old-only.txt").path))
        #expect(!hasQuarantine(sandbox.target))
        #expect(try sandbox.destinationEntries() == ["TatakiNote.app"])
    }

    @Test("AC-19: 移す先がフォルダでなければ、何も変えずにエラーになる")
    func missingDestinationFails() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try FileManager.default.removeItem(at: sandbox.destination)

        #expect(throws: ApplicationMoveError.destinationNotWritable) {
            try makeMover(sandbox: sandbox).move(from: sandbox.source, as: .removable)
        }
        #expect(sandbox.payload(of: sandbox.source) == "new")
        #expect(!FileManager.default.fileExists(atPath: sandbox.destination.path))
    }

    @Test("AC-19: 移す先に書けなければ、何も変えずにエラーになる")
    func unwritableDestinationFails() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.destination.path)

        #expect(throws: ApplicationMoveError.destinationNotWritable) {
            try makeMover(sandbox: sandbox).move(from: sandbox.source, as: .removable)
        }
        #expect(sandbox.payload(of: sandbox.source) == "new")
        #expect(try sandbox.destinationEntries().isEmpty)
    }

    @Test("AC-19: 写すのに失敗したら、前からある TatakiNote・元はそのままで、作りかけも残らない")
    func copyFailureLeavesEverythingUntouched() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeExistingTarget()
        let mover = makeMover(
            sandbox: sandbox,
            copy: { _, destination in
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try "half".write(to: destination.appendingPathComponent("partial.txt"), atomically: true, encoding: .utf8)
                throw InjectedFailure()
            }
        )

        #expect(throws: ApplicationMoveError.copyFailed) {
            try mover.move(from: sandbox.source, as: .removable)
        }
        #expect(sandbox.payload(of: sandbox.target) == "old")
        #expect(sandbox.payload(of: sandbox.source) == "new")
        #expect(try sandbox.destinationEntries() == ["TatakiNote.app"])
    }

    @Test("AC-19: 置き換えに失敗したら、前からある TatakiNote・元はそのままで、作りかけも残らない")
    func replaceFailureLeavesEverythingUntouched() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.makeExistingTarget()
        let mover = makeMover(sandbox: sandbox, replace: { _, _ in throw InjectedFailure() })

        #expect(throws: ApplicationMoveError.replaceFailed) {
            try mover.move(from: sandbox.source, as: .removable)
        }
        #expect(sandbox.payload(of: sandbox.target) == "old")
        #expect(sandbox.payload(of: sandbox.source) == "new")
        #expect(try sandbox.destinationEntries() == ["TatakiNote.app"])
    }

    @Test("AC-19: 元を消すのに失敗しても、移動は成功として扱い、元は残る")
    func discardFailureStillSucceeds() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let mover = makeMover(sandbox: sandbox, discard: { _ in throw InjectedFailure() })

        let result = try mover.move(from: sandbox.source, as: .removable)

        #expect(result.standardizedFileURL == sandbox.target.standardizedFileURL)
        #expect(sandbox.payload(of: sandbox.target) == "new")
        #expect(sandbox.payload(of: sandbox.source) == "new")
    }

    // MARK: - 開き直すコマンド

    @Test("AC-23: 開き直すコマンドは、PID とパスを別の引数で渡し、空白・引用符を含むパスでも壊れない")
    func relaunchCommandPassesArgumentsSeparately() {
        let path = "/Applications/Tataki \"Note\" $HOME.app"
        let command = AppRelauncher.relaunchCommand(appPath: path, processIdentifier: 4321)

        #expect(command.count == 6)
        #expect(Array(command.prefix(2)) == ["/bin/sh", "-c"])
        #expect(command[2].contains("kill -0 \"$1\""))
        #expect(command[2].contains("/usr/bin/open \"$2\""))
        #expect(!command[2].contains("Tataki"))
        #expect(!command[2].contains("4321"))
        #expect(command[3] == "sh")
        #expect(command[4] == "4321")
        #expect(command[5] == path)
    }

    // MARK: - ほかのプロセスの終了

    private final class ProcessRecorder {
        var terminated: [Int32] = []
        var sleeps: [TimeInterval] = []
        private var checks: [Int32: Int] = [:]
        private let runningAnswers: [Int32: Int]

        init(runningAnswers: [Int32: Int]) {
            self.runningAnswers = runningAnswers
        }

        func isRunning(_ identifier: Int32) -> Bool {
            let count = checks[identifier, default: 0]
            checks[identifier] = count + 1
            return count < runningAnswers[identifier, default: 0]
        }
    }

    private func makeTerminator(_ recorder: ProcessRecorder) -> OtherInstanceTerminator {
        OtherInstanceTerminator(
            timeout: 1,
            pollInterval: 0.2,
            isRunning: { recorder.isRunning($0) },
            terminate: { recorder.terminated.append($0) },
            sleep: { recorder.sleeps.append($0) }
        )
    }

    @Test("AC-28: 渡したプロセスが無ければ、終了も待ちもせずに成功する")
    func terminateAllWithNoProcesses() {
        let recorder = ProcessRecorder(runningAnswers: [:])

        #expect(makeTerminator(recorder).terminateAll([]))
        #expect(recorder.terminated.isEmpty)
        #expect(recorder.sleeps.isEmpty)
    }

    @Test("AC-28: 終了を頼んですぐ終わっていれば、待たずに成功する")
    func terminateAllWhenAlreadyGone() {
        let recorder = ProcessRecorder(runningAnswers: [20: 0])

        #expect(makeTerminator(recorder).terminateAll([20]))
        #expect(recorder.terminated == [20])
        #expect(recorder.sleeps.isEmpty)
    }

    @Test("AC-28: 少し待って終われば成功する")
    func terminateAllAfterWaiting() {
        let recorder = ProcessRecorder(runningAnswers: [20: 2])

        #expect(makeTerminator(recorder).terminateAll([20]))
        #expect(recorder.terminated == [20])
        #expect(recorder.sleeps == [0.2, 0.2])
    }

    @Test("AC-28: 終わらないプロセスが1つでもあれば、決めた回数だけ待って失敗する")
    func terminateAllTimesOut() {
        let recorder = ProcessRecorder(runningAnswers: [20: 0, 30: .max])

        #expect(!makeTerminator(recorder).terminateAll([20, 30]))
        #expect(recorder.terminated == [20, 30])
        #expect(recorder.sleeps.count == 5)
    }
}
