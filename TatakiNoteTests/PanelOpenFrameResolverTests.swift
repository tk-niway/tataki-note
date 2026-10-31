import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelOpenFrameResolverTests {
    private static let ownPid: pid_t = 4242

    private let editor = WatcherFixture.editor
    private let own = InsertionTarget(processIdentifier: PanelOpenFrameResolverTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let openingSize = CGSize(width: 400, height: 300)
    private let screen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780)
    )

    private func makeResolver(
        probe: FocusedElementProbeStub,
        recorder: WindowFrameLocateRecorder? = nil,
        screens: [ScreenGeometry]? = nil,
        primaryScreenFrame: CGRect? = CGRect(x: 0, y: 0, width: 1000, height: 800)
    ) -> PanelOpenFrameResolver {
        let available = screens ?? [screen]
        let locator = recorder ?? WindowFrameLocateRecorder()
        return PanelOpenFrameResolver(
            fieldProbe: probe,
            locateTargetWindowFrame: { locator.locate($0) },
            ownProcessIdentifier: Self.ownPid,
            primaryScreenFrame: { primaryScreenFrame },
            screens: { available },
            mouseLocation: { CGPoint(x: 500, y: 400) }
        )
    }

    private func resolve(
        _ resolver: PanelOpenFrameResolver,
        target: InsertionTarget?,
        mode: PanelScreen = .main,
        isSidebarOpen: Bool = false
    ) -> NSRect? {
        resolver.frame(
            target: target,
            mode: mode,
            isTrusted: true,
            observedFocus: nil,
            isSidebarOpen: isSidebarOpen,
            openingSize: { _ in openingSize }
        )
    }

    @Test("AC-2: 画面の一覧が空なら nil を返し、開く大きさを求めない")
    func noScreensReturnsNilWithoutSizing() {
        var sizingCalls = 0
        let resolver = makeResolver(probe: FocusedElementProbeStub(), screens: [])

        let frame = resolver.frame(
            target: editor,
            mode: .main,
            isTrusted: true,
            observedFocus: nil,
            isSidebarOpen: false,
            openingSize: { _ in
                sizingCalls += 1
                return openingSize
            }
        )

        #expect(frame == nil)
        #expect(sizingCalls == 0)
    }

    @Test("AC-2: 画面があれば、その画面の表示領域に収まる枠を返し、開く大きさにはその画面の表示領域を渡す")
    func returnsFrameWithinVisibleFrame() throws {
        var receivedVisibleFrames: [CGRect] = []
        let resolver = makeResolver(probe: FocusedElementProbeStub())

        let frame = resolver.frame(
            target: editor,
            mode: .main,
            isTrusted: true,
            observedFocus: nil,
            isSidebarOpen: false,
            openingSize: {
                receivedVisibleFrames.append($0)
                return openingSize
            }
        )

        let placed = try #require(frame)
        #expect(receivedVisibleFrames == [screen.visibleFrame])
        #expect(placed.size == openingSize)
        #expect(screen.visibleFrame.contains(placed))
    }

    @Test("AC-2: サイドバーが開いていると、右端を保って左へサイドバーの幅だけ広い枠を返す")
    func openSidebarExpandsLeftKeepingRightEdge() throws {
        let resolver = makeResolver(probe: FocusedElementProbeStub())

        let closed = try #require(resolve(resolver, target: editor, isSidebarOpen: false))
        let expanded = try #require(resolve(resolver, target: editor, isSidebarOpen: true))

        #expect(expanded.maxX == closed.maxX)
        #expect(expanded.minX == closed.minX - SidebarLayout.width)
        #expect(expanded.width == closed.width + SidebarLayout.width)
        #expect(expanded.minY == closed.minY)
        #expect(expanded.height == closed.height)
    }

    @Test("AC-2: 挿入先が自分自身・無しのときは、入力欄に問い合わせない(他のアプリのときは1回問い合わせる)")
    func ownAppAndNoTargetDoNotQueryFieldProbe() {
        let cases: [(name: String, target: InsertionTarget?, queries: Int)] = [
            ("自分自身", own, 0),
            ("挿入先が無い", nil, 0),
            ("他のアプリ", editor, 1),
        ]
        for (name, target, queries) in cases {
            let probe = FocusedElementProbeStub()
            let resolver = makeResolver(probe: probe)

            _ = resolve(resolver, target: target, mode: .nearFocusedField)

            #expect(probe.targets.count == queries, "\(name)")
        }
    }

    @Test("AC-2: メインの画面が分からないときは、入力欄に問い合わせずにマウスなどで画面を決める")
    func missingPrimaryScreenSkipsFieldProbe() {
        let probe = FocusedElementProbeStub()
        let resolver = makeResolver(probe: probe, primaryScreenFrame: nil)

        let frame = resolve(resolver, target: editor, mode: .nearFocusedField)

        #expect(frame != nil)
        #expect(probe.targets.isEmpty)
    }

    @Test("AC-2: 挿入先が無いときは、ウィンドウの一覧を取らない。あれば挿入先のプロセス番号で1回取る")
    func windowListIsFetchedOnlyForTarget() {
        let cases: [(name: String, target: InsertionTarget?, fetched: [pid_t])] = [
            ("挿入先が無い", nil, []),
            ("他のアプリ", editor, [editor.processIdentifier]),
        ]
        for (name, target, fetched) in cases {
            let recorder = WindowFrameLocateRecorder()
            let resolver = makeResolver(probe: FocusedElementProbeStub(), recorder: recorder)

            _ = resolve(resolver, target: target, mode: .targetWindow)

            #expect(recorder.processIdentifiers == fetched, "\(name)")
        }
    }
}
