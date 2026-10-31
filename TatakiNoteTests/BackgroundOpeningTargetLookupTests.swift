import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

nonisolated final class BlockingFocusProber: BackgroundFocusProbing, @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var probeCountValue = 0
    private var exposureCountValue = 0
    private let exposureResult: AXError
    private let probe = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)

    init(exposureResult: AXError = .success) {
        self.exposureResult = exposureResult
    }

    var probeCount: Int {
        lock.withLock { probeCountValue }
    }

    var exposureCount: Int {
        lock.withLock { exposureCountValue }
    }

    func release() {
        gate.signal()
    }

    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
        lock.withLock { probeCountValue += 1 }
        gate.wait()
        return probe
    }

    func frame(of element: AXUIElement) -> CGRect? {
        nil
    }

    func requestWebContentExposure(of target: InsertionTarget) -> AXError {
        lock.withLock { exposureCountValue += 1 }
        return exposureResult
    }
}

@MainActor
struct BackgroundOpeningTargetLookupTests {
    private let editor = MonitorFixture.editor

    private func makeExposer(result: AXError = .success) -> WebContentExposer {
        WebContentExposer(notificationCenter: NotificationCenter(), request: { _ in result })
    }

    private func request(shouldExposeWebContent: Bool = true) -> OpeningTargetLookupRequest {
        OpeningTargetLookupRequest(
            app: editor,
            observedProbe: nil,
            readsMissingFrame: true,
            shouldExposeWebContent: shouldExposeWebContent
        )
    }

    private func awaitFinish(of pending: PendingOpeningTargetLookup) async throws {
        try await waitUntil(attempts: 100, interval: .milliseconds(10)) { pending.result != nil }
    }

    // MARK: - AC-11

    @Test("AC-11: 締め切りまでに終われば結果を返し、Web の中身の依頼を頼み済みとして記録する")
    func returnsResultWithinDeadline() throws {
        let prober = BlockingFocusProber()
        prober.release()
        let exposer = makeExposer()
        let lookup = BackgroundOpeningTargetLookup(exposer: exposer, prober: prober)

        let outcome = lookup.lookUp(request(), waitingUpTo: .seconds(10))

        guard case .finished(let result) = outcome else {
            Issue.record("締め切り内に終わったのに .finished ではない")
            return
        }
        #expect(result.didQuery)
        #expect(prober.probeCount == 1)
        #expect(prober.exposureCount == 1)
        #expect(exposer.needsRequest(for: editor) == false)
    }

    @Test("AC-11: 終わらなければ待ちを返し、終わったときにメインスレッドで1回だけ知らせて、頼み済みとして記録する")
    func returnsPendingThenNotifiesOnce() async throws {
        let prober = BlockingFocusProber()
        defer { prober.release() }
        let exposer = makeExposer()
        let lookup = BackgroundOpeningTargetLookup(exposer: exposer, prober: prober)

        let outcome = lookup.lookUp(request(), waitingUpTo: .milliseconds(10))

        guard case .pending(let pending) = outcome else {
            Issue.record("締め切りを超えたのに .pending ではない")
            return
        }
        var notifiedOnMain: [Bool] = []
        pending.whenFinished { _ in notifiedOnMain.append(Thread.isMainThread) }
        #expect(pending.result == nil)
        #expect(notifiedOnMain.isEmpty)

        prober.release()
        try await awaitFinish(of: pending)

        #expect(pending.result?.didQuery == true)
        #expect(notifiedOnMain == [true])
        #expect(exposer.needsRequest(for: editor) == false)
        #expect(prober.probeCount == 1)
        #expect(prober.exposureCount == 1)
    }

    @Test("AC-11: 知らせ先の登録が終わった後でも、その場で知らせる")
    func notifiesHandlerRegisteredAfterFinish() async throws {
        let prober = BlockingFocusProber()
        defer { prober.release() }
        let lookup = BackgroundOpeningTargetLookup(exposer: makeExposer(), prober: prober)
        guard case .pending(let pending) = lookup.lookUp(request(), waitingUpTo: .milliseconds(10)) else {
            Issue.record("締め切りを超えたのに .pending ではない")
            return
        }

        prober.release()
        try await awaitFinish(of: pending)
        var callCount = 0
        pending.whenFinished { _ in callCount += 1 }

        #expect(callCount == 1)
    }

    @Test("AC-11: 知らせは2回目からは何もしない")
    func finishNotifiesOnlyOnce() async throws {
        let pending = PendingOpeningTargetLookup()
        let first = OpeningTargetLookupResult(
            probe: FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil),
            didQuery: true,
            duration: 1
        )
        let second = OpeningTargetLookupResult(
            probe: FocusedElementProbe(element: nil, lookup: .unavailable, frame: nil),
            didQuery: false,
            duration: 2
        )
        var received: [TimeInterval] = []
        pending.whenFinished { received.append($0.duration) }

        pending.finish(first)
        pending.finish(second)

        #expect(received == [1])
        #expect(pending.result?.duration == 1)
    }

    @Test("AC-11: 覚えない結果の依頼は、締め切り内でも遅れても頼み済みにしない")
    func doesNotRecordFailedRequest() async throws {
        let fastProber = BlockingFocusProber(exposureResult: .cannotComplete)
        fastProber.release()
        let fastExposer = makeExposer()
        let fastLookup = BackgroundOpeningTargetLookup(exposer: fastExposer, prober: fastProber)
        _ = fastLookup.lookUp(request(), waitingUpTo: .seconds(10))
        #expect(fastProber.exposureCount == 1)
        #expect(fastExposer.needsRequest(for: editor))

        let slowProber = BlockingFocusProber(exposureResult: .cannotComplete)
        defer { slowProber.release() }
        let slowExposer = makeExposer()
        let slowLookup = BackgroundOpeningTargetLookup(exposer: slowExposer, prober: slowProber)
        guard case .pending(let pending) = slowLookup.lookUp(request(), waitingUpTo: .milliseconds(10)) else {
            Issue.record("締め切りを超えたのに .pending ではない")
            return
        }
        slowProber.release()
        try await awaitFinish(of: pending)
        #expect(slowProber.exposureCount == 1)
        #expect(slowExposer.needsRequest(for: editor))
    }

    @Test("AC-11: 頼み済みのアプリや頼まない依頼では、Web の中身の依頼をしない")
    func skipsExposureWhenAlreadyRequestedOrNotWanted() {
        let alreadyRequested = makeExposer()
        alreadyRequested.record(.success, for: editor)
        let proberA = BlockingFocusProber()
        proberA.release()
        _ = BackgroundOpeningTargetLookup(exposer: alreadyRequested, prober: proberA)
            .lookUp(request(), waitingUpTo: .seconds(10))
        #expect(proberA.exposureCount == 0)
        #expect(proberA.probeCount == 1)

        let proberB = BlockingFocusProber()
        proberB.release()
        let notWanted = makeExposer()
        _ = BackgroundOpeningTargetLookup(exposer: notWanted, prober: proberB)
            .lookUp(request(shouldExposeWebContent: false), waitingUpTo: .seconds(10))
        #expect(proberB.exposureCount == 0)
        #expect(notWanted.needsRequest(for: editor))
    }
}
