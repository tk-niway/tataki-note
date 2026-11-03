import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelSizeControllerFindBarTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private static let bodyFrame = NSRect(x: 400, y: 100, width: 520, height: 340)
    private static let findBar = FindBarMetrics.height(isVisible: true, isReplaceShown: false)
    private static let replaceBar = FindBarMetrics.height(isVisible: true, isReplaceShown: true)

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let sidebarModel: SidebarModel
        let panel = PromptPanel(contentRect: PanelSizeControllerFindBarTests.bodyFrame)
        let animator = FakePanelFrameAnimator()
        let controller: PanelSizeController

        init(frame: NSRect = PanelSizeControllerFindBarTests.bodyFrame) throws {
            defaults = try TemporaryDefaults()
            let library = DraftLibrary(store: .inMemory)
            let session = DraftSession(panel: PanelModel(), library: library, ownProcessIdentifier: 777)
            sidebarModel = SidebarModel(settings: defaults.makeSettings(), library: library, session: session)
            controller = PanelSizeController(
                panel: panel,
                sidebarModel: sidebarModel,
                animator: animator,
                visibleFrame: { _ in PanelSizeControllerFindBarTests.screen }
            )
            panel.setFrame(frame, display: false)
            controller.applyMinimumSize()
        }

        func drag(to size: CGSize) {
            controller.windowWillStartLiveResize(motionPhase: .shown)
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            controller.windowDidEndLiveResize()
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    // MARK: - AC-32

    @Test("AC-32: 検索バーを出すと窓は上端を保ったまま検索バーの高さだけ下へ伸び、閉じると元の枠に戻る")
    func barStretchesDownAndRestores() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(fixture.panel.frame == NSRect(x: 400, y: 100 - Self.findBar, width: 520, height: 340 + Self.findBar))
        #expect(fixture.controller.findBarHeight == Self.findBar)
        #expect(!fixture.controller.isAdjustingFrameForFindBar)

        fixture.controller.syncFindBarHeight(0)

        #expect(fixture.panel.frame == Self.bodyFrame)
        #expect(fixture.controller.findBarHeight == 0)
    }

    @Test("AC-32: 画面の下端に収まらないときは上へずれ、閉じると元の位置と高さに戻る")
    func barShiftsUpWhenBelowDoesNotFit() throws {
        let frame = NSRect(x: 400, y: 10, width: 520, height: 340)
        let fixture = try Fixture(frame: frame)
        defer { fixture.cleanUp() }

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(fixture.panel.frame.minY == Self.screen.minY)
        #expect(fixture.panel.frame.height == 340 + Self.findBar)
        #expect(fixture.panel.frame.maxY == frame.maxY + (Self.findBar - frame.minY))

        fixture.controller.syncFindBarHeight(0)

        #expect(fixture.panel.frame == frame)
    }

    @Test("AC-32: 置換の欄の開閉でも窓が伸び縮みして、元に戻る")
    func replaceRowStretchesAndShrinks() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.syncFindBarHeight(Self.findBar)
        let withFindRow = fixture.panel.frame

        fixture.controller.syncFindBarHeight(Self.replaceBar)

        #expect(fixture.panel.frame.height == withFindRow.height + FindBarMetrics.replaceRowHeight)
        #expect(fixture.panel.frame.maxY == withFindRow.maxY)
        #expect(fixture.controller.findBarHeight == Self.replaceBar)

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(fixture.panel.frame == withFindRow)
    }

    @Test("AC-32: 同じ高さを合わせても窓は変わらない")
    func sameHeightDoesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.syncFindBarHeight(Self.findBar)
        let frame = fixture.panel.frame

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(fixture.panel.frame == frame)
    }

    @Test("AC-32: 検索バーによる伸び縮みはドラッグで決めた大きさとして覚えない")
    func barResizeIsNotRemembered() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.syncFindBarHeight(Self.findBar)
        fixture.controller.syncFindBarHeight(Self.replaceBar)
        fixture.controller.syncFindBarHeight(0)

        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-32: 検索バーの変更中に起きるライブリサイズ・リサイズの通知は、覚える大きさにならない")
    func resizeNotificationsDuringBarAdjustmentAreIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.isAdjustingFrameForFindBar = true
        fixture.drag(to: CGSize(width: 700, height: 500))
        fixture.controller.isAdjustingFrameForFindBar = false

        #expect(fixture.controller.sizing.heldSize == nil)

        fixture.controller.isAdjustingFrameForFindBar = true
        _ = fixture.controller.windowWillResize(
            fixture.panel,
            to: NSSize(width: 700, height: 500),
            motionPhase: .shown
        )
        fixture.panel.setFrame(NSRect(origin: fixture.panel.frame.origin, size: CGSize(width: 700, height: 500)), display: false)
        fixture.controller.windowDidResize(motionPhase: .shown)
        fixture.controller.isAdjustingFrameForFindBar = false

        #expect(fixture.controller.sizing.heldSize == nil)
    }

    @Test("AC-32: 検索バーが出ている間のドラッグは、検索バーの分を除いた大きさを覚える")
    func dragWithBarRemembersBodySizeWithoutBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.syncFindBarHeight(Self.findBar)

        fixture.drag(to: CGSize(width: 520, height: 500 + Self.findBar))

        #expect(fixture.controller.sizing.heldSize?.height == 500)
    }

    @Test("AC-32: 修飾キーのサイズ変更も、検索バーの分を除いた大きさを覚える")
    func pointerResizeWithBarRemembersBodySizeWithoutBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.syncFindBarHeight(Self.findBar)

        fixture.controller.recordPointerResize(
            fromWindowSize: CGSize(width: 520, height: 340 + Self.findBar),
            toWindowSize: CGSize(width: 520, height: 480 + Self.findBar)
        )

        #expect(fixture.controller.sizing.heldSize?.height == 480)
    }

    @Test("AC-35: サイドバーの開閉の動きの途中で高さを合わせると、動きを先に終えてから高さを変える")
    func syncFinishesSidebarSlideFirst() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.setSidebarOpen(true, isPanelPresented: true, isAnimationEnabled: true, motionPhase: .shown)
        let slideTarget = try #require(fixture.animator.calls.first?.frame)
        #expect(fixture.controller.isSidebarSliding)

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(!fixture.controller.isSidebarSliding)
        #expect(fixture.animator.jumps == [slideTarget])
        #expect(fixture.sidebarModel.isOpen)
        #expect(fixture.panel.frame.width == slideTarget.width)
        #expect(fixture.panel.frame.height == slideTarget.height + Self.findBar)
        #expect(fixture.panel.frame.maxY == slideTarget.maxY)
    }

    // MARK: - AC-36

    @Test("AC-36: 検索バーが出ている間は窓の最小の高さが検索バーの分だけ高く、閉じると今と同じに戻る")
    func minimumHeightIncludesBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let base = SidebarLayout.minimumWindowSize(isSidebarOpen: false)

        fixture.controller.syncFindBarHeight(Self.findBar)
        #expect(fixture.panel.contentMinSize == CGSize(width: base.width, height: base.height + Self.findBar))

        fixture.controller.syncFindBarHeight(Self.replaceBar)
        #expect(fixture.panel.contentMinSize == CGSize(width: base.width, height: base.height + Self.replaceBar))

        fixture.controller.syncFindBarHeight(0)
        #expect(fixture.panel.contentMinSize == base)
    }

    @Test("AC-36: サイドバーが開いていても最小の大きさは検索バーの分だけ高い")
    func minimumHeightIncludesBarWithSidebar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.setSidebarOpen(true, isPanelPresented: true, isAnimationEnabled: false, motionPhase: .shown)
        let base = SidebarLayout.minimumWindowSize(isSidebarOpen: true)

        fixture.controller.syncFindBarHeight(Self.findBar)

        #expect(fixture.panel.contentMinSize == CGSize(width: base.width, height: base.height + Self.findBar))
    }

    @Test("AC-36: 手のドラッグで小さくしても、検索バーが出ていれば最小の高さで止まる")
    func dragClampsToMinimumWithBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let base = SidebarLayout.minimumWindowSize(isSidebarOpen: false)
        fixture.controller.syncFindBarHeight(Self.findBar)

        let clamped = fixture.controller.windowWillResize(
            fixture.panel,
            to: NSSize(width: 100, height: 100),
            motionPhase: .shown
        )

        #expect(clamped == NSSize(width: base.width, height: base.height + Self.findBar))
    }

    @Test("AC-36: 検索バーが出ていないときの最小の大きさは今と同じ")
    func dragClampsToBaseMinimumWithoutBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let base = SidebarLayout.minimumWindowSize(isSidebarOpen: false)

        let clamped = fixture.controller.windowWillResize(
            fixture.panel,
            to: NSSize(width: 100, height: 100),
            motionPhase: .shown
        )

        #expect(clamped == NSSize(width: base.width, height: base.height))
    }

    @Test("AC-36: サイドバーを閉じる動きの途中でも、最小の高さに検索バーの分が入る")
    func sidebarSlideCloseKeepsBarInMinimum() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.setSidebarOpen(true, isPanelPresented: true, isAnimationEnabled: false, motionPhase: .shown)
        fixture.controller.syncFindBarHeight(Self.findBar)
        let base = SidebarLayout.minimumWindowSize(isSidebarOpen: false)

        fixture.controller.setSidebarOpen(false, isPanelPresented: true, isAnimationEnabled: true, motionPhase: .shown)

        #expect(fixture.panel.contentMinSize == CGSize(width: base.width, height: base.height + Self.findBar))
    }

    // MARK: - AC-33

    @Test("AC-33: 開く大きさは覚えた大きさに検索バーの分を足したもので、窓が持つ検索バーの高さもその値になる")
    func openingSizeAddsBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.drag(to: CGSize(width: 600, height: 400))
        let held = try #require(fixture.controller.sizing.heldSize)

        let size = fixture.controller.openingSize(in: Self.screen, findBarHeight: Self.replaceBar)

        #expect(size == CGSize(width: held.width, height: held.height + Self.replaceBar))
        #expect(fixture.controller.findBarHeight == Self.replaceBar)
        #expect(fixture.controller.sizing.heldSize == held)
    }

    @Test("AC-33: 検索バーが出ていなければ、開く大きさは覚えた大きさのまま")
    func openingSizeWithoutBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.drag(to: CGSize(width: 600, height: 400))
        let held = try #require(fixture.controller.sizing.heldSize)

        let size = fixture.controller.openingSize(in: Self.screen, findBarHeight: 0)

        #expect(size == held)
        #expect(fixture.controller.findBarHeight == 0)
    }

    @Test("AC-33: 画面に余りがなければ、検索バーの分は伸ばさず、窓が持つ高さにも入れない")
    func openingSizeLimitedByScreen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.drag(to: CGSize(width: 600, height: Self.screen.height - 10))

        let size = fixture.controller.openingSize(in: Self.screen, findBarHeight: Self.findBar)

        #expect(size.height == Self.screen.height)
        #expect(fixture.controller.findBarHeight == 10)
    }

    @Test("AC-33: 開き直しで覚えた大きさに検索バーの分が重ならない")
    func reopeningDoesNotStackBar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.drag(to: CGSize(width: 600, height: 400))
        let held = try #require(fixture.controller.sizing.heldSize)

        let first = fixture.controller.openingSize(in: Self.screen, findBarHeight: Self.findBar)
        let second = fixture.controller.openingSize(in: Self.screen, findBarHeight: Self.findBar)

        #expect(first == second)
        #expect(first.height == held.height + Self.findBar)
    }

    @Test("AC-33: 位置が決まらず真ん中に開くときは、窓が持っている検索バーの分と今の検索バーの差だけ高さを変える")
    func centeredOpeningAdjustsByDifference() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.syncFindBarHeight(Self.findBar)
        let heldWindowHeight = fixture.panel.frame.height

        fixture.controller.resetFindBarShift()
        fixture.controller.syncFindBarHeight(Self.findBar)
        fixture.controller.applyMinimumSize()

        #expect(fixture.panel.frame.height == heldWindowHeight)

        fixture.controller.resetFindBarShift()
        fixture.controller.syncFindBarHeight(Self.replaceBar)
        fixture.controller.applyMinimumSize()

        #expect(fixture.panel.frame.height == heldWindowHeight + FindBarMetrics.replaceRowHeight)
        #expect(fixture.controller.findBarHeight == Self.replaceBar)

        fixture.controller.resetFindBarShift()
        fixture.controller.syncFindBarHeight(0)

        #expect(fixture.panel.frame.height == Self.bodyFrame.height)
        #expect(fixture.controller.findBarHeight == 0)
    }
}
