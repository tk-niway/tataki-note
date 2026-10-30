import Foundation

/// 書き出しの結果。
struct DraftLibraryWriteResult: Equatable {
    let fileName: String
    let succeeded: Bool
}

/// 下書き・履歴のファイルへの書き出しを行う先。
protocol DraftLibraryWriting: AnyObject {
    /// `fileName` のファイルの書き出しを頼む。結果は `completion` でメインスレッドに返す。
    func write(
        fileName: String,
        _ job: @escaping @Sendable () throws -> Void,
        completion: @escaping @MainActor (DraftLibraryWriteResult) -> Void
    )
    /// 頼んだ書き出しが全部終わるまで待つ。
    func waitUntilIdle()
}

/// その場で書き出す書き手。
final class ImmediateDraftLibraryWriter: DraftLibraryWriting {
    init() {}

    func write(
        fileName: String,
        _ job: @escaping @Sendable () throws -> Void,
        completion: @escaping @MainActor (DraftLibraryWriteResult) -> Void
    ) {
        let succeeded: Bool
        do {
            try job()
            succeeded = true
        } catch {
            succeeded = false
        }
        completion(DraftLibraryWriteResult(fileName: fileName, succeeded: succeeded))
    }

    func waitUntilIdle() {}
}

/// 背景の直列のキューで書き出す書き手。同じファイルの、まだ始まっていない書き出しは最後のものだけ行う。
nonisolated final class BackgroundDraftLibraryWriter: DraftLibraryWriting {
    private let queue = DispatchQueue(label: "DraftLibraryWriter", qos: .utility)
    private let pending = PendingDraftLibraryWrites()

    init() {}

    func write(
        fileName: String,
        _ job: @escaping @Sendable () throws -> Void,
        completion: @escaping @MainActor (DraftLibraryWriteResult) -> Void
    ) {
        let request = DraftLibraryWriteRequest(job: job, completion: completion)
        guard pending.replace(fileName: fileName, with: request) else { return }
        ProcessInfo.processInfo.disableSuddenTermination()
        let pending = pending
        queue.async {
            defer { ProcessInfo.processInfo.enableSuddenTermination() }
            guard let latest = pending.take(fileName: fileName) else { return }
            let succeeded: Bool
            do {
                try latest.job()
                succeeded = true
            } catch {
                succeeded = false
            }
            let result = DraftLibraryWriteResult(fileName: fileName, succeeded: succeeded)
            let completion = latest.completion
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    func waitUntilIdle() {
        queue.sync {}
    }
}

private nonisolated struct DraftLibraryWriteRequest: Sendable {
    let job: @Sendable () throws -> Void
    let completion: @MainActor (DraftLibraryWriteResult) -> Void
}

private nonisolated final class PendingDraftLibraryWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: DraftLibraryWriteRequest] = [:]

    /// 待っている書き出しを置き換える。そのファイルの待ちが無かった(新しく積む必要がある)なら `true`。
    func replace(fileName: String, with request: DraftLibraryWriteRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let isNew = requests[fileName] == nil
        requests[fileName] = request
        return isNew
    }

    func take(fileName: String) -> DraftLibraryWriteRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.removeValue(forKey: fileName)
    }
}
