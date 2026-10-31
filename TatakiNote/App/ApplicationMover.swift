import AppKit

/// 移動の失敗。
enum ApplicationMoveError: Error, Equatable {
    case destinationNotWritable
    case copyFailed
    case replaceFailed
}

/// アプリを「アプリケーション」フォルダへ移す。
struct ApplicationMover {
    let destinationDirectory: URL
    let copy: (URL, URL) throws -> Void
    let discard: (URL) throws -> Void
    let replace: (URL, URL) throws -> Void

    /// 本物のファイル操作で `/Applications` へ移す。
    static let system = ApplicationMover(
        destinationDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true),
        copy: { try FileManager.default.copyItem(at: $0, to: $1) },
        discard: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        replace: { _ = try FileManager.default.replaceItemAt($0, withItemAt: $1) }
    )

    /// 移した先の URL を返す。失敗したときは、移す先にも元にも変化を残さない。
    func move(from source: URL, as kind: ApplicationMoveSource) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: destinationDirectory.path)
        else {
            throw ApplicationMoveError.destinationNotWritable
        }

        let target = destinationDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let temporary = destinationDirectory.appendingPathComponent(".TatakiNote-\(UUID().uuidString).app", isDirectory: true)

        do {
            try copy(source, temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ApplicationMoveError.copyFailed
        }

        Self.removeQuarantine(from: temporary)

        do {
            if fileManager.fileExists(atPath: target.path) {
                try replace(target, temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: target)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ApplicationMoveError.replaceFailed
        }

        if kind == .removable {
            try? discard(source)
        }
        return target
    }

    private static func removeQuarantine(from root: URL) {
        let attribute = "com.apple.quarantine"
        removexattr(root.path, attribute, XATTR_NOFOLLOW)
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return }
        for case let relativePath as String in enumerator {
            removexattr(root.appendingPathComponent(relativePath).path, attribute, XATTR_NOFOLLOW)
        }
    }
}

/// ほかのプロセスに終了を頼んで、終わるのを待つ。
struct OtherInstanceTerminator {
    let timeout: TimeInterval
    let pollInterval: TimeInterval
    let isRunning: (Int32) -> Bool
    let terminate: (Int32) -> Void
    let sleep: (TimeInterval) -> Void

    /// 本物のプロセスに終了を頼む。
    static let system = OtherInstanceTerminator(
        timeout: 10,
        pollInterval: 0.2,
        isRunning: { kill($0, 0) == 0 },
        terminate: { _ = NSRunningApplication(processIdentifier: $0)?.terminate() },
        sleep: { RunLoop.current.run(until: Date(timeIntervalSinceNow: $0)) }
    )

    /// 渡したプロセスに終了を頼み、すべて終わるまで待つ。時間内に終われば true。
    func terminateAll(_ identifiers: [Int32]) -> Bool {
        guard !identifiers.isEmpty else { return true }
        identifiers.forEach(terminate)
        let maximumPolls = Int((timeout / pollInterval).rounded(.up))
        var polls = 0
        while identifiers.contains(where: isRunning) {
            if polls >= maximumPolls { return false }
            sleep(pollInterval)
            polls += 1
        }
        return true
    }
}
