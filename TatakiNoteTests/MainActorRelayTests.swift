import Foundation
import Testing
@testable import TatakiNote

private nonisolated final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    private var mainThreadFlags: [Bool] = []

    func append(_ value: Int, isMain: Bool) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
        mainThreadFlags.append(isMain)
    }

    var recorded: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    var allOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags.allSatisfy { $0 }
    }
}

private final class FlagBox {
    var ran = false
}

@MainActor
struct MainActorRelayTests {
    @Test("AC-1: 背景のスレッドから続けて頼んだ処理は、頼んだ順に1回ずつ、メインスレッドで行われる")
    func runsInOrderOnceOnMainThread() async throws {
        let relay = MainActorRelay()
        let recorder = OrderRecorder()
        let thread = Thread { @Sendable in
            for index in 0..<100 {
                relay.send { recorder.append(index, isMain: Thread.isMainThread) }
            }
        }
        thread.start()

        let arrived = try await waitUntil(attempts: 200, interval: .milliseconds(10)) {
            recorder.recorded.count >= 100
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(arrived)
        #expect(recorder.recorded == Array(0..<100))
        #expect(recorder.allOnMainThread)
    }

    @Test("AC-2: メインから頼んだ処理は、send を呼んだその場では行われず、その後に行われる")
    func doesNotRunInPlace() async throws {
        let relay = MainActorRelay()
        let box = FlagBox()

        relay.send { box.ran = true }
        #expect(!box.ran)

        let arrived = try await waitUntil(attempts: 200, interval: .milliseconds(10)) { box.ran }
        #expect(arrived)
        #expect(box.ran)
    }
}
