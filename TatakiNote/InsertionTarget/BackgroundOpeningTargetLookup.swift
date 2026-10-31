import ApplicationServices
import Foundation

/// メインスレッドの外から呼べる、挿入先のアプリへの AX の問い合わせ。
nonisolated protocol BackgroundFocusProbing: Sendable {
    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe
    func frame(of element: AXUIElement) -> CGRect?
    func requestWebContentExposure(of target: InsertionTarget) -> AXError
}

extension AXFocusedTextInputInspector: nonisolated BackgroundFocusProbing {
    nonisolated func requestWebContentExposure(of target: InsertionTarget) -> AXError {
        Self.exposeWebContent(of: target)
    }
}

/// 開くときの挿入先の調べを、メインスレッドの外で行う。
final class BackgroundOpeningTargetLookup: OpeningTargetLookup {
    private let exposer: WebContentExposer
    private let prober: any BackgroundFocusProbing
    private let now: @Sendable () -> Date

    init(
        exposer: WebContentExposer,
        prober: any BackgroundFocusProbing = AXFocusedTextInputInspector(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.exposer = exposer
        self.prober = prober
        self.now = now
    }

    func lookUp(_ request: OpeningTargetLookupRequest, waitingUpTo deadline: Duration) -> OpeningTargetLookupOutcome {
        let requestsExposure = request.shouldExposeWebContent && exposer.needsRequest(for: request.app)
        let job = OpeningTargetLookupJob()
        let prober = prober
        let now = now
        let worker = Thread { @Sendable in
            var exposureError: AXError?
            let result = request.perform(
                now: now,
                exposeWebContent: {
                    if requestsExposure {
                        exposureError = prober.requestWebContentExposure(of: request.app)
                    }
                },
                probeFocusedElement: { prober.probeFocusedElement(in: $0, readsFrame: $1) },
                frame: { prober.frame(of: $0) }
            )
            job.complete(OpeningTargetLookupJobOutput(result: result, exposureError: exposureError))
        }
        worker.qualityOfService = .userInteractive
        worker.start()

        let components = deadline.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        _ = job.waitForCompletion(timeout: .now() + seconds)

        let pending = PendingOpeningTargetLookup()
        let exposer = exposer
        let app = request.app
        let output = job.abandonUnlessFinished { output in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error = output.exposureError {
                        exposer.record(error, for: app)
                    }
                    pending.finish(output.result)
                }
            }
        }
        guard let output else { return .pending(pending) }
        if let error = output.exposureError {
            exposer.record(error, for: app)
        }
        return .finished(output.result)
    }
}

private nonisolated struct OpeningTargetLookupJobOutput: Sendable {
    let result: OpeningTargetLookupResult
    let exposureError: AXError?
}

private nonisolated final class OpeningTargetLookupJob: @unchecked Sendable {
    private enum State {
        case running
        case finished(OpeningTargetLookupJobOutput)
        case abandoned(@Sendable (OpeningTargetLookupJobOutput) -> Void)
    }

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var state = State.running

    func waitForCompletion(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }

    func complete(_ output: OpeningTargetLookupJobOutput) {
        lock.lock()
        switch state {
        case .running:
            state = .finished(output)
            lock.unlock()
            semaphore.signal()
        case .abandoned(let handler):
            lock.unlock()
            handler(output)
        case .finished:
            lock.unlock()
        }
    }

    func abandonUnlessFinished(
        _ handler: @escaping @Sendable (OpeningTargetLookupJobOutput) -> Void
    ) -> OpeningTargetLookupJobOutput? {
        lock.lock()
        defer { lock.unlock() }
        if case .finished(let output) = state {
            return output
        }
        state = .abandoned(handler)
        return nil
    }
}
