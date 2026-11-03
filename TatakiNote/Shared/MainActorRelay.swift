/// メインスレッドの外から頼んだ処理を、頼んだ順に MainActor で1つずつ行う。
nonisolated final class MainActorRelay: Sendable {
    private let continuation: AsyncStream<@MainActor () -> Void>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: (@MainActor () -> Void).self)
        self.continuation = continuation
        Task { @MainActor in
            for await work in stream {
                work()
            }
        }
    }

    deinit {
        continuation.finish()
    }

    /// `work` を、前に頼んだ処理の後に MainActor で行う。呼んだその場では行わない。
    func send(_ work: @escaping @MainActor () -> Void) {
        continuation.yield(work)
    }
}
