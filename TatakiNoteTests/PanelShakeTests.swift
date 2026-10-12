import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelShakeTests {
    @MainActor
    private final class StepSleeper {
        private(set) var durations: [Duration] = []
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func sleep(_ duration: Duration) async {
            durations.append(duration)
            await withCheckedContinuation { waiting.append($0) }
        }

        func advance() async {
            await settle()
            let pending = waiting
            waiting = []
            for continuation in pending {
                continuation.resume()
            }
            await settle()
        }

        private func settle() async {
            for _ in 0..<8 {
                await Task.yield()
            }
        }
    }

    private static let restOrigin = CGPoint(x: 100, y: 200)

    private static func makeWindow() -> NSPanel {
        NSPanel(
            contentRect: NSRect(origin: restOrigin, size: CGSize(width: 200, height: 100)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
    }

    private static func xs(_ offsets: [CGFloat]) -> [CGFloat] {
        offsets.map { restOrigin.x + $0 }
    }

    // MARK: - 純粋な値

    @Test("AC-8: 揺れは −9・8・−6・4・−2・0pt の 6 歩で、1 歩 70ms、合わせて 420ms")
    func offsetsAndDuration() {
        #expect(PanelShake.offsets == [-9, 8, -6, 4, -2, 0])
        #expect(PanelShake.stepDuration == .milliseconds(70))
        #expect(PanelShake.stepDuration * PanelShake.offsets.count == .milliseconds(420))
        #expect(PanelShake.offsets.last == 0)
    }

    @Test("AC-8: 次の歩へ進めるのは、位置が前の歩で置いた位置と同じか、x が 0.5pt 以内の差のときだけ")
    func shouldContinueBoundaries() {
        let placed = CGPoint(x: 100, y: 200)
        #expect(PanelShake.shouldContinue(currentOrigin: placed, lastPlacedOrigin: placed))
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 100.4, y: 200), lastPlacedOrigin: placed))
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 99.5, y: 200), lastPlacedOrigin: placed))
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 101, y: 200), lastPlacedOrigin: placed) == false)
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 99, y: 200), lastPlacedOrigin: placed) == false)
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 400, y: 200), lastPlacedOrigin: placed) == false)
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 100, y: 205), lastPlacedOrigin: placed) == false)
        #expect(PanelShake.shouldContinue(currentOrigin: CGPoint(x: 100, y: 199), lastPlacedOrigin: placed) == false)
    }

    @Test("AC-8: 揺らし始めてよいのは開ききっているときだけ。開く・閉じる動きの途中と閉じているときは揺らさない")
    func canStartOnlyWhenShown() {
        #expect(PanelShake.canStart(motionPhase: .shown))
        #expect(PanelShake.canStart(motionPhase: .opening) == false)
        #expect(PanelShake.canStart(motionPhase: .closing) == false)
        #expect(PanelShake.canStart(motionPhase: .hidden) == false)
    }

    // MARK: - 窓の動き

    @Test("AC-8: 窓は元の位置から −9・8・−6・4・−2・0pt の順に動き、待ちは 70ms ずつ、y は変わらない")
    func shakeMovesWindowStepByStep() async {
        let sleeper = StepSleeper()
        let shaker = PanelShaker(sleep: { await sleeper.sleep($0) })
        let window = Self.makeWindow()

        shaker.shake(window)
        #expect(window.frame.origin == Self.restOrigin)

        var observed: [CGFloat] = []
        for _ in PanelShake.offsets {
            await sleeper.advance()
            observed.append(window.frame.origin.x)
            #expect(window.frame.origin.y == Self.restOrigin.y)
        }

        #expect(observed == Self.xs(PanelShake.offsets))
        #expect(sleeper.durations == Array(repeating: .milliseconds(70), count: PanelShake.offsets.count))
        #expect(window.frame.origin == Self.restOrigin)
    }

    @Test("AC-8: 揺れの途中でもう一度揺らすと、元の位置に戻して 1 歩目から始め直し、元の位置はずれない")
    func shakeAgainRestartsFromRestOrigin() async {
        let sleeper = StepSleeper()
        let shaker = PanelShaker(sleep: { await sleeper.sleep($0) })
        let window = Self.makeWindow()

        shaker.shake(window)
        await sleeper.advance()
        await sleeper.advance()
        #expect(window.frame.origin.x == Self.restOrigin.x + 8)

        shaker.shake(window)
        #expect(window.frame.origin == Self.restOrigin)

        var observed: [CGFloat] = []
        for _ in PanelShake.offsets {
            await sleeper.advance()
            observed.append(window.frame.origin.x)
        }

        #expect(observed == Self.xs(PanelShake.offsets))
        #expect(window.frame.origin == Self.restOrigin)
    }

    @Test("AC-8: 揺れの途中で他から位置が変わったら、次の歩で止まり、元の位置へは戻さない")
    func movedByOthersStopsWithoutRestoring() async {
        let sleeper = StepSleeper()
        let shaker = PanelShaker(sleep: { await sleeper.sleep($0) })
        let window = Self.makeWindow()
        let dragged = CGPoint(x: 400, y: 300)

        shaker.shake(window)
        await sleeper.advance()
        await sleeper.advance()
        window.setFrameOrigin(dragged)

        await sleeper.advance()
        #expect(window.frame.origin == dragged)
        await sleeper.advance()
        await sleeper.advance()
        #expect(window.frame.origin == dragged)

        shaker.shake(window)
        await sleeper.advance()
        #expect(window.frame.origin.x == dragged.x - 9)
        #expect(window.frame.origin.y == dragged.y)
    }

    @Test("AC-8: 揺れの途中で止めると元の位置に戻り、以後の歩は窓を動かさない")
    func stopRestoresAndHaltsSteps() async {
        let sleeper = StepSleeper()
        let shaker = PanelShaker(sleep: { await sleeper.sleep($0) })
        let window = Self.makeWindow()

        shaker.shake(window)
        await sleeper.advance()
        await sleeper.advance()
        #expect(window.frame.origin.x == Self.restOrigin.x + 8)

        shaker.stop(window)
        #expect(window.frame.origin == Self.restOrigin)

        for _ in PanelShake.offsets {
            await sleeper.advance()
            #expect(window.frame.origin == Self.restOrigin)
        }
    }

    @Test("AC-8: 揺れていないときに止めても、窓の位置は変わらない")
    func stopWhenIdleKeepsOrigin() async {
        let sleeper = StepSleeper()
        let shaker = PanelShaker(sleep: { await sleeper.sleep($0) })
        let window = Self.makeWindow()
        let moved = CGPoint(x: 150, y: 250)

        shaker.stop(window)
        #expect(window.frame.origin == Self.restOrigin)

        shaker.shake(window)
        for _ in PanelShake.offsets {
            await sleeper.advance()
        }
        window.setFrameOrigin(moved)
        shaker.stop(window)
        #expect(window.frame.origin == moved)
    }
}
