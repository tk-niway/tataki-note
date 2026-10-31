import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelMotionControllerTests {
    private static let restFrame = NSRect(x: 300, y: 200, width: 600, height: 400)

    @MainActor
    private final class Recorder {
        var restoreCount = 0
        var ghosts: [NSWindow] = []
        var canMakeGhost = true

        func makeGhost(from source: NSWindow) -> NSWindow? {
            guard canMakeGhost else { return nil }
            let ghost = NSWindow(
                contentRect: source.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: true
            )
            ghosts.append(ghost)
            return ghost
        }
    }

    @MainActor
    private final class Fixture {
        let panel = NSPanel(
            contentRect: PanelMotionControllerTests.restFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let animator = FakePanelFrameAnimator()
        let recorder = Recorder()
        let controller: PanelMotionController

        var restoreCount: Int { recorder.restoreCount }
        var ghosts: [NSWindow] { recorder.ghosts }
        var canMakeGhost: Bool {
            get { recorder.canMakeGhost }
            set { recorder.canMakeGhost = newValue }
        }

        init() {
            panel.setFrame(PanelMotionControllerTests.restFrame, display: false)
            let recorder = recorder
            controller = PanelMotionController(
                panel: panel,
                animator: animator,
                restoreMinimumSize: { recorder.restoreCount += 1 },
                makeGhost: { recorder.makeGhost(from: $0) }
            )
        }

        func cleanUp() {
            panel.orderOut(nil)
            for ghost in recorder.ghosts {
                ghost.orderOut(nil)
            }
        }
    }

    @MainActor
    private final class CompletionCounter {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }

    // MARK: - 表示

    @Test("AC-4: アニメーションがオフなら、動きなしで表示になり、動きの呼び出しをしない")
    func presentWithoutAnimationShowsImmediately() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)

        #expect(fixture.controller.phase == .shown)
        #expect(fixture.panel.isVisible)
        #expect(fixture.panel.frame == Self.restFrame)
        #expect(fixture.animator.calls.isEmpty)
        #expect(fixture.restoreCount == 1)
    }

    @Test("AC-4: アニメーションがオンなら、線から開き、動きの終わりで表示になる")
    func presentWithAnimationOpensFromLineThenShows() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: true)

        #expect(fixture.controller.phase == .opening)
        #expect(fixture.panel.isVisible)
        #expect(fixture.panel.frame == PanelMotion.lineFrame(of: Self.restFrame))
        #expect(fixture.panel.contentMinSize == NSSize(width: 1, height: 1))
        let call = try #require(fixture.animator.calls.first)
        #expect(call.window === fixture.panel)
        #expect(call.frame == Self.restFrame)
        #expect(call.curve == .easeOut)
        #expect(fixture.restoreCount == 0)

        fixture.animator.finish(0)

        #expect(fixture.controller.phase == .shown)
        #expect(fixture.panel.frame == Self.restFrame)
        #expect(fixture.restoreCount == 1)
    }

    // MARK: - 非表示

    @Test("AC-4: アニメーションがオフなら、動きなしで非表示になり、保留の処理をすぐ呼ぶ")
    func hideWithoutAnimationHidesImmediately() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let counter = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)

        fixture.controller.hide(isAnimationEnabled: false, then: { counter.record() })

        #expect(fixture.controller.phase == .hidden)
        #expect(fixture.panel.isVisible == false)
        #expect(fixture.animator.calls.isEmpty)
        #expect(fixture.ghosts.isEmpty)
        #expect(counter.count == 1)
    }

    @Test("AC-4: 閉じる動きの終わりで、保留の処理を1回だけ呼ぶ")
    func hideAnimationCallsCompletionOnceAtEnd() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let counter = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)

        fixture.controller.hide(isAnimationEnabled: true, then: { counter.record() })

        #expect(fixture.controller.phase == .closing)
        #expect(fixture.panel.isVisible == false)
        let ghost = try #require(fixture.ghosts.first)
        #expect(ghost.isVisible)
        let call = try #require(fixture.animator.calls.first)
        #expect(call.window === ghost)
        #expect(call.frame == PanelMotion.lineFrame(of: Self.restFrame))
        #expect(call.curve == .easeIn)
        #expect(counter.count == 0)

        fixture.animator.finish(0)

        #expect(fixture.controller.phase == .hidden)
        #expect(ghost.isVisible == false)
        #expect(counter.count == 1)

        fixture.animator.finish(0)

        #expect(counter.count == 1)
    }

    @Test("AC-4: 開く途中に閉じると、枠を本来の枠に戻してから写しを縮める")
    func hideWhileOpeningRestoresFrame() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: true)

        fixture.controller.hide(isAnimationEnabled: true)

        #expect(fixture.controller.phase == .closing)
        #expect(fixture.animator.jumps == [Self.restFrame])
        #expect(fixture.panel.isVisible == false)
        #expect(fixture.restoreCount == 1)
        #expect(fixture.animator.calls.count == 2)
    }

    @Test("AC-4: 閉じる途中のもう一度の非表示は何もしない")
    func hideWhileClosingDoesNothing() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let first = CompletionCounter()
        let second = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)
        fixture.controller.hide(isAnimationEnabled: true, then: { first.record() })

        fixture.controller.hide(isAnimationEnabled: true, then: { second.record() })

        #expect(fixture.controller.phase == .closing)
        #expect(fixture.ghosts.count == 1)
        #expect(fixture.animator.calls.count == 1)
        #expect(second.count == 0)

        fixture.animator.finish(0)

        #expect(first.count == 1)
        #expect(second.count == 0)
    }

    @Test("AC-4: 写しが作れないときは、動きなしで隠し、保留の処理をすぐ呼ぶ")
    func hideWithoutGhostHidesImmediately() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let counter = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)
        fixture.canMakeGhost = false

        fixture.controller.hide(isAnimationEnabled: true, then: { counter.record() })

        #expect(fixture.controller.phase == .hidden)
        #expect(fixture.panel.isVisible == false)
        #expect(fixture.animator.calls.isEmpty)
        #expect(counter.count == 1)
    }

    // MARK: - 止める

    @Test("AC-4: 閉じる途中に止めると、保留の処理を呼ばずに捨て、古い動きの終わりを無視する")
    func stopWhileClosingDiscardsCompletion() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let counter = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)
        fixture.controller.hide(isAnimationEnabled: true, then: { counter.record() })
        let ghost = try #require(fixture.ghosts.first)

        fixture.controller.stop()

        #expect(fixture.controller.phase == .hidden)
        #expect(ghost.isVisible == false)
        #expect(counter.count == 0)

        fixture.animator.finish(0)

        #expect(fixture.controller.phase == .hidden)
        #expect(counter.count == 0)
    }

    @Test("AC-4: 開く途中に止めると、本来の枠へ跳ばし、古い動きの終わりを無視する")
    func stopWhileOpeningJumpsToRestFrame() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: true)
        let restoreCountBefore = fixture.restoreCount

        fixture.controller.stop()

        #expect(fixture.controller.phase == .hidden)
        #expect(fixture.animator.jumps == [Self.restFrame])

        fixture.animator.finish(0)

        #expect(fixture.controller.phase == .hidden)
        #expect(fixture.restoreCount == restoreCountBefore)
    }

    @Test("AC-4: 表示中や非表示のときに止めても何も変えない")
    func stopWhenNotMovingDoesNothing() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.stop()
        #expect(fixture.controller.phase == .hidden)

        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)
        fixture.controller.stop()

        #expect(fixture.controller.phase == .shown)
        #expect(fixture.panel.isVisible)
        #expect(fixture.animator.jumps.isEmpty)
    }

    @Test("AC-4: 動きなしで隠すと、写しを消し、保留の処理を捨て、古い動きの終わりを無視する")
    func hideWithoutMotionDiscardsPendingWork() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let counter = CompletionCounter()
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: false)
        fixture.controller.hide(isAnimationEnabled: true, then: { counter.record() })
        let ghost = try #require(fixture.ghosts.first)

        fixture.controller.hideWithoutMotion()

        #expect(fixture.controller.phase == .hidden)
        #expect(ghost.isVisible == false)

        fixture.animator.finish(0)

        #expect(counter.count == 0)
        #expect(fixture.controller.phase == .hidden)
    }

    @Test("AC-4: 開く途中に動きなしで隠すと、枠を本来の枠に戻す")
    func hideWithoutMotionWhileOpeningRestoresFrame() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.present(at: Self.restFrame, isAnimationEnabled: true)

        fixture.controller.hideWithoutMotion()

        #expect(fixture.controller.phase == .hidden)
        #expect(fixture.panel.isVisible == false)
        #expect(fixture.animator.jumps == [Self.restFrame])
        #expect(fixture.panel.frame == Self.restFrame)
    }
}
