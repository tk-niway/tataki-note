import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelPointerControllerTests {
    private static let panelFrame = NSRect(x: 400, y: 300, width: 520, height: 340)
    private static let sidebarPanelFrame = NSRect(x: 400, y: 300, width: 740, height: 340)
    private static let insidePoint = CGPoint(x: 700, y: 450)
    private static let bottomRightPoint = CGPoint(x: 900, y: 320)
    private static let sidebarBottomRightPoint = CGPoint(x: 1100, y: 320)
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)

    @MainActor
    private final class Environment {
        var mouse = PanelPointerControllerTests.insidePoint
        var isMouseButtonPressed = false
        var screenTopLimit: CGFloat?
        var availability = PanelPointerAvailability(isPanelShown: true, isSidebarSliding: false, isSidebarOpen: false)
        var willBegin: () -> Void = {}
        var willBeginCount = 0
        var mouseReadCount = 0
        var heldFlags: NSEvent.ModifierFlags = []
        var resizes: [(from: CGSize, to: CGSize)] = []
    }

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let settings: AppSettings
        let sidebarModel: SidebarModel
        let panel: PromptPanel
        let spy = PanelPointerEventMonitorSpy()
        let sizeController: PanelSizeController
        let environment = Environment()
        let controller: PanelPointerController

        init(frame: NSRect? = nil, isSidebarOpen: Bool = false) throws {
            let frame = frame ?? PanelPointerControllerTests.panelFrame
            defaults = try TemporaryDefaults()
            settings = defaults.makeSettings()
            let library = DraftLibrary(store: .inMemory)
            let session = DraftSession(panel: PanelModel(), library: library, ownProcessIdentifier: 777)
            sidebarModel = SidebarModel(settings: settings, library: library, session: session)
            if isSidebarOpen {
                sidebarModel.setOpen(true)
            }
            let panel = PromptPanel(contentRect: frame)
            panel.setFrame(frame, display: false)
            self.panel = panel
            let sizeController = PanelSizeController(panel: panel, sidebarModel: sidebarModel, animator: FakePanelFrameAnimator())
            self.sizeController = sizeController
            let environment = environment
            environment.availability.isSidebarOpen = isSidebarOpen
            controller = PanelPointerController(
                panel: panel,
                settings: settings,
                monitor: spy,
                availability: { environment.availability },
                willBegin: {
                    environment.willBeginCount += 1
                    environment.willBegin()
                },
                didResize: { from, to in
                    environment.resizes.append((from, to))
                    sizeController.recordPointerResize(fromWindowSize: from, toWindowSize: to)
                },
                mouseLocation: {
                    environment.mouseReadCount += 1
                    return environment.mouse
                },
                isMouseButtonPressed: { environment.isMouseButtonPressed },
                screenTopLimit: { _ in environment.screenTopLimit },
                currentModifierFlags: { environment.heldFlags }
            )
        }

        var isMoving: Bool {
            if case .moving = controller.state { return true }
            return false
        }

        var isResizing: Bool {
            if case .resizing = controller.state { return true }
            return false
        }

        func send(_ kind: PanelPointerEvent.Kind, _ flags: NSEvent.ModifierFlags, at point: CGPoint? = nil) {
            if let point {
                environment.mouse = point
            }
            controller.handle(PanelPointerEvent(kind: kind, modifierFlags: flags))
        }

        func cleanUp() {
            defaults.remove()
        }
    }

    // MARK: - 種類の振り分け

    @Test("AC-7: NSEvent の種類を、見張りのイベントの種類に振り分ける。マスクに無い種類は nil")
    func eventTypesMapToKinds() {
        let table: [(NSEvent.EventType, PanelPointerEvent.Kind?)] = [
            (.mouseMoved, .moved),
            (.flagsChanged, .modifiersChanged),
            (.leftMouseDown, .buttonDown),
            (.rightMouseDown, .buttonDown),
            (.otherMouseDown, .buttonDown),
            (.leftMouseDragged, .dragged),
            (.rightMouseDragged, .dragged),
            (.otherMouseDragged, .dragged),
            (.leftMouseUp, nil),
            (.keyDown, nil),
            (.scrollWheel, nil)
        ]
        for (eventType, kind) in table {
            #expect(PanelPointerEvent.Kind(eventType: eventType) == kind, "\(eventType)")
        }
    }

    // MARK: - 移動

    @Test("AC-5: 移動はカーソルの動きの分だけ原点を動かし、大きさは変えず、覚える大きさも変えない")
    func movingShiftsOriginOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.isMoving)
        #expect(fixture.panel.frame == Self.panelFrame)

        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))

        #expect(fixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
        #expect(fixture.environment.resizes.isEmpty)
        #expect(fixture.sizeController.sizing.heldSize == nil)
    }

    @Test("AC-5: 修飾キーが設定の組み合わせと一致しなければ何もせず、同じ組み合わせが続く間は位置も画面も読まない")
    func nonMatchingModifiersDoNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.moved, [], at: CGPoint(x: 730, y: 470))
        #expect(fixture.environment.mouseReadCount == 0)

        fixture.send(.moved, [.command, .shift], at: CGPoint(x: 740, y: 480))
        fixture.send(.moved, [.command, .shift], at: CGPoint(x: 750, y: 490))
        #expect(fixture.environment.mouseReadCount == 1)

        fixture.send(.modifiersChanged, [.control])
        fixture.send(.modifiersChanged, [.control])
        #expect(fixture.environment.mouseReadCount == 2)
        #expect(fixture.environment.willBeginCount == 0)
        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)
    }

    @Test("AC-5: パネルの外では始まらず、パネルが表示中でなければ始まらない")
    func doesNotStartOutsidePanelOrWhenNotShown() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.command], at: CGPoint(x: 100, y: 100))
        #expect(fixture.controller.state == .idle)

        fixture.environment.availability.isPanelShown = false
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.controller.state == .idle)
        #expect(fixture.environment.willBeginCount == 0)
    }

    // MARK: - 押した瞬間の位置

    @Test("AC-16: パネルの外で押して押したまま入っても始まらず、離してパネルの上で押し直すと始まる")
    func pressedOutsideThenEnteringDoesNotBegin() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.command], at: CGPoint(x: 100, y: 100))
        fixture.send(.moved, [.command], at: Self.insidePoint)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)

        fixture.send(.modifiersChanged, [], at: Self.insidePoint)
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.isMoving)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(fixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
    }

    @Test("AC-16: パネルが表示中でないときに押した押下は、パネルが出ても始まらない")
    func pressedWhileNotShownDoesNotBegin() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.environment.availability.isPanelShown = false
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        fixture.environment.availability.isPanelShown = true
        fixture.send(.moved, [.command], at: Self.insidePoint)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))

        #expect(fixture.controller.state == .idle)
        #expect(fixture.environment.willBeginCount == 0)
        #expect(fixture.panel.frame == Self.panelFrame)
    }

    @Test("AC-17: パネルの上で押した押下は、ボタンで止まった後に外へ出て戻ると、また始まる")
    func pressedOverPanelRestartsAfterButtonStop() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.isMoving)
        fixture.send(.buttonDown, [.command], at: CGPoint(x: 760, y: 500))
        #expect(fixture.controller.state == .idle)

        fixture.send(.moved, [.command], at: CGPoint(x: 100, y: 100))
        #expect(fixture.controller.state == .idle)
        fixture.send(.moved, [.command], at: Self.insidePoint)
        #expect(fixture.isMoving)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(fixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
    }

    @Test("AC-17: 動かしている途中にカーソルがパネルの外で持ち替えると、移動は止まり、サイズ変更は始まらない")
    func switchingOutsidePanelStopsWithoutResizing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.environment.screenTopLimit = 650

        fixture.send(.modifiersChanged, [.command])
        fixture.send(.moved, [.command], at: CGPoint(x: 700, y: 800))
        let clamped = NSRect(x: 400, y: 310, width: 520, height: 340)
        #expect(fixture.panel.frame == clamped)
        #expect(fixture.isMoving)

        fixture.send(.modifiersChanged, [.option], at: CGPoint(x: 700, y: 800))
        #expect(fixture.controller.state == .idle)
        fixture.send(.moved, [.option], at: Self.insidePoint)
        fixture.send(.moved, [.option], at: CGPoint(x: 800, y: 400))

        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == clamped)
        #expect(fixture.environment.resizes.isEmpty)
    }

    @Test("AC-18: 押した瞬間が届かず、カーソルの動きだけが届くときは、組み合わせが変わった最初の位置で決まる")
    func movedEventsAloneDecideAtFirstChange() throws {
        let outsideFixture = try Fixture()
        defer { outsideFixture.cleanUp() }
        outsideFixture.send(.moved, [.command], at: CGPoint(x: 100, y: 100))
        outsideFixture.send(.moved, [.command], at: Self.insidePoint)
        #expect(outsideFixture.controller.state == .idle)

        let insideFixture = try Fixture()
        defer { insideFixture.cleanUp() }
        insideFixture.send(.moved, [.command], at: Self.insidePoint)
        #expect(insideFixture.isMoving)
        insideFixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(insideFixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
    }

    @Test("AC-19: 修飾キーを押したまま見張りを始めると、パネルの上でも始まらず、離して押し直すと始まる")
    func heldModifiersAtStartDoNotBegin() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.environment.heldFlags = .command

        fixture.controller.start()
        fixture.send(.moved, [.command], at: Self.insidePoint)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)

        fixture.send(.modifiersChanged, [], at: Self.insidePoint)
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.isMoving)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))
        #expect(fixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
    }

    @Test("AC-19: 設定と一致しない組み合わせへの変化も押下の判定に使われ、外で足して離した押下は外で押したものになる")
    func unmatchedCombinationRenewsPress() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.buttonDown, [.command], at: Self.insidePoint)
        #expect(fixture.controller.state == .idle)

        let far = CGPoint(x: 100, y: 100)
        fixture.send(.modifiersChanged, [.control, .command], at: far)
        fixture.send(.modifiersChanged, [.command], at: far)
        fixture.send(.moved, [.command], at: Self.insidePoint)
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))

        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)
    }

    // MARK: - 止まる

    @Test("AC-7: ボタンを押す・修飾キーを離す・ボタンを押したまま修飾キーが変わると、動きが止まって枠が変わらない")
    func buttonOrModifierReleaseStopsMovement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.command])
        fixture.send(.buttonDown, [.command], at: CGPoint(x: 760, y: 500))
        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)

        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.isMoving)
        fixture.send(.moved, [], at: CGPoint(x: 760, y: 500))
        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)

        fixture.environment.isMouseButtonPressed = true
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.controller.state == .idle)
        fixture.send(.dragged, [.command], at: CGPoint(x: 760, y: 500))
        #expect(fixture.panel.frame == Self.panelFrame)
    }

    @Test("AC-7: 見張りを止めると動きの途中の状態を捨てる")
    func stopResetsGesture() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.controller.start()
        #expect(fixture.spy.startCount == 1)
        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.isMoving)

        fixture.controller.stop()

        #expect(fixture.controller.state == .idle)
        #expect(fixture.spy.stopCount == 1)
        fixture.spy.send(PanelPointerEvent(kind: .moved, modifierFlags: [.command]))
        #expect(fixture.panel.frame == Self.panelFrame)
    }

    // MARK: - サイズ変更

    @Test("AC-12: サイズ変更で変えた大きさを覚える大きさにする。移動では覚えない")
    func resizeRecordsHeldSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.option], at: Self.bottomRightPoint)
        #expect(fixture.isResizing)
        fixture.send(.moved, [.option], at: CGPoint(x: 950, y: 270))

        #expect(fixture.panel.frame == NSRect(x: 400, y: 250, width: 570, height: 390))
        #expect(fixture.environment.resizes.count == 1)
        #expect(fixture.environment.resizes.first?.from == CGSize(width: 520, height: 340))
        #expect(fixture.environment.resizes.first?.to == CGSize(width: 570, height: 390))
        #expect(fixture.sizeController.sizing.heldSize == CGSize(width: 570, height: 390))
    }

    @Test("AC-12: サイドバーが開いていても、覚える大きさにサイドバーの幅を含めない")
    func resizeHeldSizeExcludesSidebarWidth() throws {
        let fixture = try Fixture(frame: Self.sidebarPanelFrame, isSidebarOpen: true)
        defer { fixture.cleanUp() }

        fixture.send(.modifiersChanged, [.option], at: Self.sidebarBottomRightPoint)
        #expect(fixture.isResizing)
        fixture.send(.moved, [.option], at: CGPoint(x: 1150, y: 270))

        #expect(fixture.panel.frame == NSRect(x: 400, y: 250, width: 790, height: 390))
        #expect(fixture.sizeController.sizing.heldSize == CGSize(width: 570, height: 390))
    }

    @Test("AC-12: 覚えた大きさは、空のまま開き直すと捨て、本文があれば残る")
    func heldSizeFromResizeIsDroppedWhenReopenedEmpty() async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = .off
        let controller = PanelControllerFactory.make(
            settings: settings,
            ownProcessIdentifier: Self.ownPid,
            animator: FakePanelFrameAnimator()
        )
        defer { controller.panel.orderOut(nil) }
        controller.targetOverride = {
            InsertionTarget(processIdentifier: Self.ownPid, bundleIdentifier: "com.example.TextEdit", localizedName: "TextEdit")
        }
        controller.open()
        let opened = controller.panel.frame.size
        let resized = CGSize(width: opened.width + 80, height: opened.height + 60)

        controller.sizeController.recordPointerResize(fromWindowSize: opened, toWindowSize: resized)
        #expect(controller.heldPanelSize == resized)

        controller.model.text = "abc"
        controller.close()
        controller.open()
        #expect(controller.heldPanelSize == resized)
        #expect(controller.panel.frame.size == resized)

        controller.model.text = ""
        controller.close()
        controller.open()
        #expect(controller.heldPanelSize == nil)
        #expect(controller.panel.frame.size == opened)
    }

    // MARK: - 揺れ・キー

    @Test("AC-11: 始めるときに揺れを止め、揺れる前の位置を起点に動かす")
    func beginStopsShakeAndAnchorsAtRestoredFrame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let panel = fixture.panel
        let restoredOrigin = Self.panelFrame.origin
        panel.setFrameOrigin(CGPoint(x: restoredOrigin.x + 8, y: restoredOrigin.y))
        fixture.environment.willBegin = { panel.setFrameOrigin(restoredOrigin) }

        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.environment.willBeginCount == 1)
        #expect(fixture.panel.frame.origin == restoredOrigin)

        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 450))

        #expect(fixture.panel.frame == NSRect(x: 430, y: 300, width: 520, height: 340))
        #expect(fixture.environment.willBeginCount == 1)
    }

    @Test("AC-11: パネルがキーでも前に出てもいなくても枠が変わり、処理でキーにも前にもしない")
    func worksWithoutKeyOrVisibleAndDoesNotTakeFocus() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(!fixture.panel.isKeyWindow)
        #expect(!fixture.panel.isVisible)

        fixture.send(.modifiersChanged, [.command])
        fixture.send(.moved, [.command], at: CGPoint(x: 740, y: 460))
        fixture.send(.modifiersChanged, [.option], at: Self.bottomRightPoint)
        fixture.send(.moved, [.option], at: CGPoint(x: 950, y: 270))

        #expect(fixture.panel.frame != Self.panelFrame)
        #expect(!fixture.panel.isKeyWindow)
        #expect(!fixture.panel.isVisible)
    }

    // MARK: - 設定の変更

    @Test("AC-13: 設定で組み合わせを変えると、次のイベントからその組み合わせで働く")
    func changedModifiersApplyFromNextEvent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.settings.selectPointerModifiers([.control], for: .move))

        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.controller.state == .idle)

        fixture.send(.modifiersChanged, [.control])
        #expect(fixture.isMoving)
        fixture.send(.moved, [.control], at: CGPoint(x: 730, y: 470))
        #expect(fixture.panel.frame == NSRect(x: 430, y: 320, width: 520, height: 340))
    }

    @Test("AC-13: 全部外すとすぐ使えなくなり、動かしている途中なら止まる")
    func clearingModifiersDisablesImmediately() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.send(.modifiersChanged, [.command])
        #expect(fixture.isMoving)

        #expect(fixture.settings.selectPointerModifiers([], for: .move))
        fixture.send(.moved, [.command], at: CGPoint(x: 730, y: 470))

        #expect(fixture.controller.state == .idle)
        #expect(fixture.panel.frame == Self.panelFrame)
        fixture.send(.modifiersChanged, [.command], at: Self.insidePoint)
        #expect(fixture.controller.state == .idle)
    }

    // MARK: - 開閉

    @MainActor
    private struct OpenCloseFixture {
        let controller: PanelController
        let spy: PanelPointerEventMonitorSpy
        let inserter: InserterStub
    }

    private func withOpenCloseFixture(_ body: (OpenCloseFixture) async throws -> Void) async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = .off
        settings.commitKey = .commandShiftReturn
        let spy = PanelPointerEventMonitorSpy()
        let inserter = InserterStub(result: .inserted)
        let controller = PanelControllerFactory.make(
            settings: settings,
            inserter: inserter,
            ownProcessIdentifier: Self.ownPid,
            animator: FakePanelFrameAnimator(),
            pointerEventMonitor: spy
        )
        defer { controller.panel.orderOut(nil) }
        try await body(OpenCloseFixture(controller: controller, spy: spy, inserter: inserter))
    }

    @Test("AC-12: パネルを開くと見張りが始まり、動きありで閉じると止まる。開いている間に開き直しても始め直さない")
    func openStartsAndAnimatedCloseStops() async throws {
        try await withOpenCloseFixture { fixture in
            #expect(fixture.spy.startCount == 0)

            fixture.controller.openWithoutTarget()
            #expect(fixture.spy.startCount == 1)
            #expect(fixture.spy.stopCount == 0)

            fixture.controller.open()
            #expect(fixture.spy.startCount == 1)

            fixture.controller.close()
            #expect(fixture.spy.stopCount == 1)
        }
    }

    @Test("AC-12: 動きなしで閉じても見張りが止まり、開き直すと見張りがまた始まる")
    func immediateCloseStopsAndReopenRestarts() async throws {
        try await withOpenCloseFixture { fixture in
            fixture.controller.openWithoutTarget()
            #expect(fixture.spy.startCount == 1)

            fixture.controller.closeImmediately()
            #expect(fixture.spy.stopCount == 1)

            fixture.controller.openWithoutTarget()
            #expect(fixture.spy.startCount == 2)
        }
    }

    @Test("AC-12: 確定してパネルが閉じると見張りが止まる")
    func commitStopsMonitoring() async throws {
        try await withOpenCloseFixture { fixture in
            fixture.controller.targetOverride = {
                InsertionTarget(processIdentifier: Self.ownPid, bundleIdentifier: "com.example.TextEdit", localizedName: "TextEdit")
            }
            fixture.controller.open()
            #expect(fixture.spy.startCount == 1)
            let stopsBefore = fixture.spy.stopCount
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            await yieldUntil { fixture.spy.stopCount > stopsBefore && fixture.inserter.calls.count == 1 }

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.spy.stopCount > stopsBefore)
        }
    }
}
