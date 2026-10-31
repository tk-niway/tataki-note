import ApplicationServices
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

    // MARK: - 入力欄を読まない口

    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780)
    )
    private let screenB = ScreenGeometry(
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 780)
    )
    private let windowOnB = CGRect(x: 1100, y: 100, width: 600, height: 500)
    private let fieldOnBQuartz = CGRect(x: 1200, y: 100, width: 200, height: 40)

    private func observedFocus(frame: CGRect?) -> ObservedFocus {
        ObservedFocus(
            processIdentifier: editor.processIdentifier,
            probe: FocusedElementProbe(
                element: AXUIElementCreateApplication(pid_t.max),
                lookup: WatcherFixture.textFieldLookup,
                frame: frame
            )
        )
    }

    private func resolveFrame(
        _ resolver: PanelOpenFrameResolver,
        mode: PanelScreen,
        observedFocus: ObservedFocus?,
        queriesField: Bool
    ) -> NSRect? {
        resolver.frame(
            target: editor,
            mode: mode,
            isTrusted: true,
            observedFocus: observedFocus,
            queriesField: queriesField,
            isSidebarOpen: false,
            openingSize: { _ in openingSize }
        )
    }

    @Test("AC-3: 「入力欄の近く」で入力欄を読まないときは、挿入先のウィンドウと最も重なる画面の中央に出し、入力欄を問い合わせない")
    func nearFieldWithoutQueryCentersOnTargetWindowScreen() throws {
        let probe = FocusedElementProbeStub()
        probe.elementFrame = fieldOnBQuartz
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = windowOnB
        let resolver = makeResolver(probe: probe, recorder: recorder, screens: [screenA, screenB])

        let frame = try #require(resolveFrame(resolver, mode: .nearFocusedField, observedFocus: nil, queriesField: false))

        #expect(frame == PanelPlacement.centeredFrame(size: openingSize, in: screenB.visibleFrame))
        #expect(probe.targets.isEmpty)
        #expect(probe.frameRequests.isEmpty)
    }

    @Test("AC-3: 「入力欄の近く」で入力欄を読まず、ウィンドウも分からないときは、マウスのある画面の中央に出す")
    func nearFieldWithoutQueryCentersOnMouseScreenWithoutWindow() throws {
        let probe = FocusedElementProbeStub()
        let resolver = makeResolver(probe: probe, screens: [screenB, screenA])

        let frame = try #require(resolveFrame(resolver, mode: .nearFocusedField, observedFocus: nil, queriesField: false))

        #expect(frame == PanelPlacement.centeredFrame(size: openingSize, in: screenA.visibleFrame))
        #expect(probe.targets.isEmpty)
        #expect(probe.frameRequests.isEmpty)
    }

    @Test("AC-3: 入力欄を読まないときは、見張りの結果に枠が無くても要素から枠を読まない。読むときは1回読む")
    func observedFocusWithoutFrameIsNotReadWhenNotQuerying() throws {
        let cases: [(queriesField: Bool, frameRequests: Int)] = [(false, 0), (true, 1)]
        for (queriesField, frameRequests) in cases {
            let probe = FocusedElementProbeStub()
            probe.elementFrame = fieldOnBQuartz
            let resolver = makeResolver(probe: probe, screens: [screenA, screenB])

            let frame = try #require(
                resolveFrame(resolver, mode: .nearFocusedField, observedFocus: observedFocus(frame: nil), queriesField: queriesField)
            )

            #expect(probe.frameRequests.count == frameRequests, "\(queriesField)")
            #expect(probe.targets.isEmpty, "\(queriesField)")
            let isCentered = frame == PanelPlacement.centeredFrame(size: openingSize, in: screenA.visibleFrame)
            #expect(isCentered == !queriesField, "\(queriesField)")
        }
    }

    @Test("AC-3: 入力欄を読まなくても、見張りの結果に枠があればそれを使って入力欄の近くに出す")
    func observedFrameIsUsedWhenNotQuerying() throws {
        let probe = FocusedElementProbeStub()
        let resolver = makeResolver(probe: probe, screens: [screenA, screenB])
        let observed = observedFocus(frame: fieldOnBQuartz)

        let withoutQuery = try #require(resolveFrame(resolver, mode: .nearFocusedField, observedFocus: observed, queriesField: false))
        let withQuery = try #require(resolveFrame(resolver, mode: .nearFocusedField, observedFocus: observed, queriesField: true))

        #expect(withoutQuery == withQuery)
        #expect(withoutQuery != PanelPlacement.centeredFrame(size: openingSize, in: screenB.visibleFrame))
        #expect(screenB.visibleFrame.contains(withoutQuery))
        #expect(probe.targets.isEmpty)
        #expect(probe.frameRequests.isEmpty)
    }

    @Test("AC-3: 入力欄を読まないときの入力欄の枠は、許可・見張りの結果・枠の有無に応じて決まり、問い合わせない")
    func fieldFrameWithoutQueryUsesOnlyObservedFrame() {
        let probe = FocusedElementProbeStub()
        probe.elementFrame = fieldOnBQuartz
        let cases: [(name: String, mode: PanelScreen, isTrusted: Bool, observed: ObservedFocus?, hasFrame: Bool)] = [
            ("同じアプリ・枠あり", .nearFocusedField, true, observedFocus(frame: fieldOnBQuartz), true),
            ("同じアプリ・枠なし", .nearFocusedField, true, observedFocus(frame: nil), false),
            ("見張りの結果なし", .nearFocusedField, true, nil, false),
            ("許可なし", .nearFocusedField, false, observedFocus(frame: fieldOnBQuartz), false),
            ("入力欄の近くでない", .main, true, observedFocus(frame: fieldOnBQuartz), false),
        ]
        for (name, mode, isTrusted, observed, hasFrame) in cases {
            let frame = PanelOpenPlacement.fieldFrame(
                mode: mode,
                isTrusted: isTrusted,
                target: editor,
                probe: probe,
                observedFocus: observed,
                primaryScreenHeight: 800,
                queriesMissingFrame: false
            )
            #expect((frame != nil) == hasFrame, "\(name)")
        }
        #expect(probe.targets.isEmpty)
        #expect(probe.frameRequests.isEmpty)
    }

    // MARK: - AC-4

    @Test("AC-4: 「挿入先のウィンドウがある画面」「マウスの近く」「メインの画面」で先に出す位置は、入力欄の位置が分かっているときと同じ", arguments: [PanelScreen.targetWindow, PanelScreen.mouse, PanelScreen.main])
    func otherModesPlaceTheSameWithoutFieldQuery(mode: PanelScreen) throws {
        let screens = [screenA, screenB]
        let known = observedFocus(frame: fieldOnBQuartz)
        let recorderForKnown = WindowFrameLocateRecorder()
        recorderForKnown.frame = windowOnB
        let knownProbe = FocusedElementProbeStub()
        let withField = try #require(
            resolveFrame(
                makeResolver(probe: knownProbe, recorder: recorderForKnown, screens: screens),
                mode: mode,
                observedFocus: known,
                queriesField: true
            )
        )

        let recorder = WindowFrameLocateRecorder()
        recorder.frame = windowOnB
        let probe = FocusedElementProbeStub()
        let withoutField = try #require(
            resolveFrame(
                makeResolver(probe: probe, recorder: recorder, screens: screens),
                mode: mode,
                observedFocus: nil,
                queriesField: false
            )
        )

        #expect(withoutField == withField)
        #expect(probe.targets.isEmpty)
        #expect(probe.frameRequests.isEmpty)
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
