import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelSizeControllerTests {
    private static let visibleFrame = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private static let bodyFrame = NSRect(x: 400, y: 100, width: 520, height: 340)
    private static let expandedFrame = NSRect(x: 180, y: 100, width: 740, height: 340)

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let sidebarModel: SidebarModel
        let panel = PromptPanel(contentRect: PanelSizeControllerTests.bodyFrame)
        let animator = FakePanelFrameAnimator()
        let controller: PanelSizeController

        init() throws {
            defaults = try TemporaryDefaults()
            settings = defaults.makeSettings()
            let library = DraftLibrary(store: .inMemory)
            let session = DraftSession(panel: PanelModel(), library: library, ownProcessIdentifier: 777)
            sidebarModel = SidebarModel(settings: settings, library: library, session: session)
            controller = PanelSizeController(
                panel: panel,
                sidebarModel: sidebarModel,
                animator: animator,
                visibleFrame: { _ in PanelSizeControllerTests.visibleFrame }
            )
            panel.setFrame(PanelSizeControllerTests.bodyFrame, display: false)
        }

        func setSidebarOpen(
            _ isOpen: Bool,
            isPanelPresented: Bool = true,
            isAnimationEnabled: Bool = false,
            motionPhase: PanelMotionPhase = .shown
        ) {
            controller.setSidebarOpen(
                isOpen,
                isPanelPresented: isPanelPresented,
                isAnimationEnabled: isAnimationEnabled,
                motionPhase: motionPhase
            )
        }

        func drag(to size: CGSize, motionPhase: PanelMotionPhase = .shown) {
            controller.windowWillStartLiveResize(motionPhase: motionPhase)
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            controller.windowDidEndLiveResize()
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    // MARK: - サイドバーの開閉

    @Test("AC-3: パネルが開いているときにサイドバーを開閉すると、窓の枠と最小の大きさを変える")
    func togglingSidebarChangesFrameAndMinimumSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.setSidebarOpen(true)

        #expect(fixture.panel.frame == Self.expandedFrame)
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: true))
        #expect(!fixture.controller.isAdjustingFrameForSidebar)

        fixture.setSidebarOpen(false)

        #expect(fixture.panel.frame == Self.bodyFrame)
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: false))
        #expect(!fixture.controller.isAdjustingFrameForSidebar)
    }

    @Test("AC-3: パネルが閉じているときにサイドバーを開閉しても、窓の枠は変えず、開閉の状態と最小の大きさだけ変える")
    func togglingSidebarWhileClosedKeepsFrame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.setSidebarOpen(true, isPanelPresented: false)

        #expect(fixture.panel.frame == Self.bodyFrame)
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: true))
        #expect(fixture.animator.calls.isEmpty)

        fixture.setSidebarOpen(false, isPanelPresented: false)

        #expect(fixture.panel.frame == Self.bodyFrame)
        #expect(!fixture.sidebarModel.isOpen)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: false))
    }

    @Test("AC-3: アニメーションがオンで動きが表示中なら、サイドバーの開閉は枠を滑らせ、終わると状態を確定する")
    func slidingSidebarFinishesOnCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.setSidebarOpen(true, isAnimationEnabled: true)

        let call = try #require(fixture.animator.calls.first)
        #expect(fixture.animator.calls.count == 1)
        #expect(call.frame == Self.expandedFrame)
        #expect(call.curve == .easeOut)
        #expect(fixture.controller.isSidebarSliding)
        #expect(fixture.controller.isAdjustingFrameForSidebar)
        #expect(fixture.sidebarModel.slidingBodyWidth == Self.bodyFrame.width)

        fixture.animator.finish(0)

        #expect(fixture.panel.frame == Self.expandedFrame)
        #expect(!fixture.controller.isSidebarSliding)
        #expect(!fixture.controller.isAdjustingFrameForSidebar)
        #expect(fixture.sidebarModel.slidingBodyWidth == nil)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: true))
    }

    @Test("AC-3: 動きが表示中でないときは、アニメーションがオンでも滑らせずにすぐ枠を変える")
    func sidebarChangesImmediatelyOutsideShownPhase() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.setSidebarOpen(true, isAnimationEnabled: true, motionPhase: .opening)

        #expect(fixture.animator.calls.isEmpty)
        #expect(fixture.panel.frame == Self.expandedFrame)
        #expect(!fixture.controller.isSidebarSliding)
    }

    @Test("AC-3: 滑りの途中で次の開閉が来ると、最後の枠へ跳んで終えてから次の滑りを始め、前の滑りの完了は何もしない")
    func nextToggleDuringSlideJumpsToEnd() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.setSidebarOpen(true, isAnimationEnabled: true)

        fixture.setSidebarOpen(false, isAnimationEnabled: true)

        #expect(fixture.animator.jumps.last == Self.expandedFrame)
        #expect(fixture.animator.calls.count == 2)
        #expect(fixture.animator.calls[1].windowFrame == Self.expandedFrame)
        #expect(fixture.animator.calls[1].frame == Self.bodyFrame)
        #expect(fixture.animator.calls[1].curve == .easeIn)

        fixture.animator.finish(0, moving: false)

        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.controller.isSidebarSliding)
        #expect(fixture.sidebarModel.slidingBodyWidth == Self.bodyFrame.width)

        fixture.animator.finish(1)

        #expect(!fixture.sidebarModel.isOpen)
        #expect(!fixture.controller.isSidebarSliding)
        #expect(fixture.panel.frame == Self.bodyFrame)
    }

    @Test("AC-3: 滑りの途中で finishSidebarSlide を呼ぶと、最後の枠へ跳んで状態と最小の大きさを確定する")
    func finishSidebarSlideJumpsToLastFrame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.setSidebarOpen(true, isAnimationEnabled: true)

        fixture.controller.finishSidebarSlide()

        #expect(fixture.animator.jumps == [Self.expandedFrame])
        #expect(fixture.panel.frame == Self.expandedFrame)
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.sidebarModel.slidingBodyWidth == nil)
        #expect(!fixture.controller.isSidebarSliding)
        #expect(!fixture.controller.isAdjustingFrameForSidebar)
        #expect(fixture.panel.contentMinSize == SidebarLayout.minimumWindowSize(isSidebarOpen: true))

        fixture.controller.finishSidebarSlide()

        #expect(fixture.animator.jumps.count == 1)
    }

    // MARK: - 大きさを覚える

    @Test("AC-3: ドラッグの開始から終了で、変わった本文の大きさを覚える")
    func dragHoldsBodySize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.drag(to: CGSize(width: 640, height: 420))

        #expect(fixture.controller.sizing.heldSize == CGSize(width: 640, height: 420))
    }

    @Test("AC-3: サイドバーを開いているときのドラッグは、サイドバーの幅を除いた本文の大きさを覚える")
    func dragWithSidebarOpenHoldsBodySizeWithoutSidebar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.setSidebarOpen(true)

        fixture.drag(to: CGSize(width: 840, height: 420))

        #expect(fixture.controller.sizing.heldSize == CGSize(width: 840 - SidebarLayout.width, height: 420))
    }

    @Test("AC-3: サイドバーの調整中のドラッグは、本文の大きさを覚えない")
    func dragWhileAdjustingForSidebarIsNotHeld() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.isAdjustingFrameForSidebar = true

        fixture.drag(to: CGSize(width: 640, height: 420))

        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-3: 開閉の動きの途中(開く・閉じる)のドラッグは、本文の大きさを覚えない")
    func dragDuringMotionIsNotHeld() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.drag(to: CGSize(width: 640, height: 420), motionPhase: .opening)
        fixture.drag(to: CGSize(width: 700, height: 460), motionPhase: .closing)

        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-3: ライブリサイズの通知が来ない大きさの変更も、動きが表示中なら本文の大きさを覚える")
    func resizeWithoutLiveResizeIsHeld() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let dragged = CGSize(width: 700, height: 500)

        _ = fixture.controller.windowWillResize(fixture.panel, to: dragged, motionPhase: .shown)
        fixture.panel.setFrame(NSRect(origin: fixture.panel.frame.origin, size: dragged), display: false)
        fixture.controller.windowDidResize(motionPhase: .shown)

        #expect(fixture.controller.sizing.heldSize == dragged)
    }

    @Test("AC-3: 開く動きの間と滑りの途中の windowWillResize は、渡された大きさをそのまま返し、覚えない")
    func resizeDuringOpeningOrSlideReturnsGivenSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let tiny = CGSize(width: 10, height: 10)

        #expect(fixture.controller.windowWillResize(fixture.panel, to: tiny, motionPhase: .opening) == tiny)
        fixture.controller.windowDidResize(motionPhase: .opening)

        fixture.setSidebarOpen(true, isAnimationEnabled: true)

        #expect(fixture.controller.windowWillResize(fixture.panel, to: tiny, motionPhase: .shown) == tiny)
        fixture.controller.windowDidResize(motionPhase: .shown)
        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-3: 滑りの途中で終わった大きさの変更は、本文の大きさを覚えない")
    func resizeCompletedDuringSlideIsNotHeld() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        _ = fixture.controller.windowWillResize(fixture.panel, to: CGSize(width: 700, height: 500), motionPhase: .shown)
        fixture.setSidebarOpen(true, isAnimationEnabled: true)

        fixture.panel.setFrame(NSRect(origin: fixture.panel.frame.origin, size: CGSize(width: 700, height: 500)), display: false)
        fixture.controller.windowDidResize(motionPhase: .shown)

        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-3: windowWillResize は、サイドバーの開閉に合わせた最小の大きさで抑えた大きさを返す")
    func resizeIsClampedToMinimumSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let tiny = CGSize(width: 10, height: 10)

        #expect(fixture.controller.windowWillResize(fixture.panel, to: tiny, motionPhase: .shown) == PanelSizing.minimumSize)

        fixture.setSidebarOpen(true)

        #expect(
            fixture.controller.windowWillResize(fixture.panel, to: tiny, motionPhase: .shown)
                == SidebarLayout.minimumWindowSize(isSidebarOpen: true)
        )
    }
}
