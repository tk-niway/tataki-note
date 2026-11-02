import CoreGraphics
import Testing
@testable import TatakiNote

struct PanelPointerGestureTests {
    private let frame = CGRect(x: 100, y: 100, width: 520, height: 340)
    private let inside = CGPoint(x: 300, y: 300)

    private func context(
        frame: CGRect? = nil,
        isShown: Bool = true,
        isSliding: Bool = false,
        isSidebarOpen: Bool = false,
        move: Set<PanelPointerModifier> = [.command],
        resize: Set<PanelPointerModifier> = [.option],
        limit: CGFloat? = 1000
    ) -> PanelPointerContext {
        PanelPointerContext(
            panelFrame: frame ?? self.frame,
            isPanelShown: isShown,
            isSidebarSliding: isSliding,
            isSidebarOpen: isSidebarOpen,
            moveModifiers: move,
            resizeModifiers: resize,
            screenTopLimit: limit
        )
    }

    private func sample(
        _ pointer: CGPoint? = nil,
        _ modifiers: Set<PanelPointerModifier> = [.command],
        pressed: Bool = false
    ) -> PanelPointerSample {
        PanelPointerSample(pointer: pointer ?? inside, modifiers: modifiers, isMouseButtonPressed: pressed)
    }

    private func movingGesture() -> PanelPointerGesture {
        var gesture = PanelPointerGesture()
        gesture.begin(.move, pointer: inside, frame: frame, isSidebarOpen: false)
        return gesture
    }

    private func resizingGesture(at pointer: CGPoint, frame: CGRect? = nil, isSidebarOpen: Bool = false) -> PanelPointerGesture {
        var gesture = PanelPointerGesture()
        gesture.begin(.resize, pointer: pointer, frame: frame ?? self.frame, isSidebarOpen: isSidebarOpen)
        return gesture
    }

    // MARK: 始める条件

    @Test("AC-4: 移動が ⌘ のとき ⌘ だけで始まる")
    func startsWithExactCommand() {
        #expect(PanelPointerGesture.startingAction(for: sample(), in: context()) == .move)
    }

    @Test("AC-4: ⌃⌘・⌥⌘ では始まらない")
    func doesNotStartWithExtraModifier() {
        #expect(PanelPointerGesture.startingAction(for: sample(nil, [.control, .command]), in: context()) == nil)
        #expect(PanelPointerGesture.startingAction(for: sample(nil, [.option, .command]), in: context()) == nil)
    }

    @Test("AC-4: 修飾キーを押していないと始まらない")
    func doesNotStartWithoutModifiers() {
        #expect(PanelPointerGesture.startingAction(for: sample(nil, []), in: context()) == nil)
    }

    @Test("AC-4: 組み合わせが空の操作はどの修飾キーでも始まらない")
    func emptyCombinationNeverStarts() {
        let noMove = context(move: [])
        #expect(PanelPointerGesture.startingAction(for: sample(nil, []), in: noMove) == nil)
        #expect(PanelPointerGesture.startingAction(for: sample(nil, [.command]), in: noMove) == nil)
        let noResize = context(resize: [])
        #expect(PanelPointerGesture.startingAction(for: sample(nil, [.option]), in: noResize) == nil)
        #expect(PanelPointerGesture.startingAction(for: sample(nil, []), in: noResize) == nil)
    }

    @Test("AC-4: サイズ変更の組み合わせでサイズ変更が始まる")
    func startsResize() {
        #expect(PanelPointerGesture.startingAction(for: sample(nil, [.option]), in: context()) == .resize)
    }

    @Test("AC-4: 移動とサイズ変更が同じ組み合わせなら移動")
    func sameCombinationPrefersMove() {
        let same = context(move: [.command], resize: [.command])
        #expect(PanelPointerGesture.startingAction(for: sample(), in: same) == .move)
    }

    @Test("AC-5: パネルの外にカーソルがあるときは始まらない")
    func doesNotStartOutsidePanel() {
        #expect(PanelPointerGesture.startingAction(for: sample(CGPoint(x: 50, y: 50)), in: context()) == nil)
        #expect(PanelPointerGesture.startingAction(for: sample(CGPoint(x: 620, y: 300)), in: context()) == nil)
        #expect(PanelPointerGesture.startingAction(for: sample(CGPoint(x: 300, y: 440)), in: context()) == nil)
    }

    @Test("AC-7: ボタンを押している間は始まらない")
    func doesNotStartWhilePressed() {
        #expect(PanelPointerGesture.startingAction(for: sample(pressed: true), in: context()) == nil)
    }

    @Test("AC-8: サイドバーの上でも始まる")
    func startsOverSidebar() {
        let wide = CGRect(x: 100, y: 100, width: 740, height: 340)
        let overSidebar = CGPoint(x: 150, y: 300)
        let ctx = context(frame: wide, isSidebarOpen: true)
        #expect(PanelPointerGesture.startingAction(for: sample(overSidebar), in: ctx) == .move)
    }

    @Test("AC-10: 開く・閉じる動きの途中・閉じている間は始まらない")
    func doesNotStartWhenPanelNotShown() {
        #expect(PanelPointerGesture.startingAction(for: sample(), in: context(isShown: false)) == nil)
    }

    @Test("AC-10: サイドバーの開閉の動きの途中は始まらない")
    func doesNotStartWhileSidebarSliding() {
        #expect(PanelPointerGesture.startingAction(for: sample(), in: context(isSliding: true)) == nil)
    }

    // MARK: handle: idle

    @Test("AC-4: idle で条件がそろうと begin を返し、状態は idle のまま")
    func idleBegins() {
        var gesture = PanelPointerGesture()
        #expect(gesture.handle(sample(), in: context()) == .begin(.move))
        #expect(gesture.state == .idle)
    }

    @Test("AC-5: idle で条件がそろわなければ何もしない")
    func idleDoesNothing() {
        var gesture = PanelPointerGesture()
        #expect(gesture.handle(sample(CGPoint(x: 5, y: 5)), in: context()) == .none)
        #expect(gesture.handle(sample(nil, []), in: context()) == .none)
        #expect(gesture.state == .idle)
    }

    @Test("AC-5: begin で起点を置くと moving になる")
    func beginMoveSetsAnchor() {
        let gesture = movingGesture()
        #expect(gesture.state == .moving(PanelPointerAnchor(frame: frame, pointer: inside, isSidebarOpen: false)))
    }

    @Test("AC-6: begin のサイズ変更は、カーソルのある区画の角を選ぶ")
    func beginResizePicksCorner() {
        let gesture = resizingGesture(at: CGPoint(x: 110, y: 110))
        #expect(gesture.state == .resizing(
            PanelPointerAnchor(frame: frame, pointer: CGPoint(x: 110, y: 110), isSidebarOpen: false),
            .bottomLeft
        ))
    }

    @Test("AC-7: reset で idle に戻る")
    func resetReturnsToIdle() {
        var gesture = movingGesture()
        gesture.reset()
        #expect(gesture.state == .idle)
    }

    // MARK: handle: 移動

    @Test("AC-5: 移動の続きで、カーソルの動きと同じだけ原点が動く(setOrigin)")
    func movingReturnsSetOrigin() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 330, y: 280)), in: context())
        #expect(step == .setOrigin(CGPoint(x: 130, y: 80)))
    }

    @Test("AC-5: 移動で動いていなければ none")
    func movingWithoutDeltaIsNone() {
        var gesture = movingGesture()
        #expect(gesture.handle(sample(), in: context()) == .none)
    }

    @Test("AC-5: 移動は枠を入れ直した後も起点からの差で動く")
    func movingUsesAnchorNotCurrentFrame() {
        var gesture = movingGesture()
        let moved = frame.offsetBy(dx: 30, dy: -20)
        let step = gesture.handle(sample(CGPoint(x: 340, y: 290)), in: context(frame: moved))
        #expect(step == .setOrigin(CGPoint(x: 140, y: 90)))
    }

    @Test("AC-9: 移動は画面の上端を越えない")
    func movingStopsAtTop() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 300, y: 1000)), in: context())
        #expect(step == .setOrigin(CGPoint(x: 100, y: 660)))
    }

    // MARK: handle: サイズ変更

    @Test("AC-6: サイズ変更はカーソルの動きと同じだけ角が動く(setFrame)")
    func resizingReturnsSetFrame() {
        var gesture = resizingGesture(at: CGPoint(x: 600, y: 420))
        let step = gesture.handle(sample(CGPoint(x: 640, y: 450), [.option]), in: context())
        #expect(step == .setFrame(CGRect(x: 100, y: 100, width: 560, height: 370)))
    }

    @Test("AC-6: 最小の大きさに当たって枠が変わらないときは none")
    func resizingAtMinimumIsNone() {
        let small = CGRect(x: 100, y: 100, width: 320, height: 160)
        var gesture = resizingGesture(at: CGPoint(x: 400, y: 240), frame: small)
        let step = gesture.handle(sample(CGPoint(x: 300, y: 200), [.option]), in: context(frame: small))
        #expect(step == .none)
    }

    @Test("AC-6: 最小の大きさで止まっても反対の角は動かない")
    func resizingStopsAtMinimum() {
        var gesture = resizingGesture(at: CGPoint(x: 600, y: 420))
        let step = gesture.handle(sample(CGPoint(x: -400, y: -400), [.option]), in: context())
        #expect(step == .setFrame(CGRect(x: 100, y: 100, width: 320, height: 160)))
    }

    @Test("AC-6: サイドバーが開いていれば最小の幅は 540")
    func resizingMinimumWithSidebar() {
        let wide = CGRect(x: 100, y: 100, width: 740, height: 340)
        var gesture = resizingGesture(at: CGPoint(x: 800, y: 120), frame: wide, isSidebarOpen: true)
        let step = gesture.handle(sample(CGPoint(x: 0, y: 120), [.option]), in: context(frame: wide, isSidebarOpen: true))
        #expect(step == .setFrame(CGRect(x: 100, y: 100, width: 540, height: 340)))
    }

    @Test("AC-8: サイドバーの上から始めたサイズ変更は左の角が動く")
    func resizingFromSidebarMovesLeftCorner() {
        let wide = CGRect(x: 100, y: 100, width: 740, height: 340)
        let gesture = resizingGesture(at: CGPoint(x: 150, y: 120), frame: wide, isSidebarOpen: true)
        guard case .resizing(_, let corner) = gesture.state else {
            Issue.record("resizing になっていない")
            return
        }
        #expect(corner == .bottomLeft)
    }

    @Test("AC-8: 始まった後はカーソルがパネルの外へ出ても続く")
    func continuesOutsidePanel() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 2000, y: 300)), in: context())
        #expect(step == .setOrigin(CGPoint(x: 1800, y: 100)))
        #expect(gesture.state != .idle)
    }

    // MARK: handle: 止める

    @Test("AC-7: 修飾キーを離すと止まり、その後カーソルが動いても枠は変わらない")
    func releasingStops() {
        var gesture = movingGesture()
        #expect(gesture.handle(sample(CGPoint(x: 330, y: 300), []), in: context()) == .none)
        #expect(gesture.state == .idle)
        #expect(gesture.handle(sample(CGPoint(x: 400, y: 300), []), in: context()) == .none)
    }

    @Test("AC-7: ほかの修飾キーを足すと止まる")
    func addingModifierStops() {
        var gesture = movingGesture()
        #expect(gesture.handle(sample(CGPoint(x: 330, y: 300), [.command, .shift]), in: context()) == .none)
        #expect(gesture.state == .idle)
    }

    @Test("AC-7: マウスボタンを押すと止まり、押している間は始まらない")
    func pressingStops() {
        var gesture = movingGesture()
        #expect(gesture.handle(sample(CGPoint(x: 330, y: 300), pressed: true), in: context()) == .none)
        #expect(gesture.state == .idle)
        #expect(gesture.handle(sample(CGPoint(x: 340, y: 300), pressed: true), in: context()) == .none)
        #expect(gesture.state == .idle)
    }

    @Test("AC-7: 止まった後に条件がそろうと、その位置から新しく始まる")
    func restartsAfterStopping() {
        var gesture = movingGesture()
        _ = gesture.handle(sample(CGPoint(x: 330, y: 300), []), in: context())
        let restart = CGPoint(x: 400, y: 300)
        #expect(gesture.handle(sample(restart), in: context()) == .begin(.move))
        gesture.begin(.move, pointer: restart, frame: frame, isSidebarOpen: false)
        #expect(gesture.handle(sample(restart), in: context()) == .none)
    }

    @Test("AC-7: 移動の途中で修飾キーをサイズ変更の組み合わせに持ち替えるとサイズ変更が始まる")
    func switchingFromMoveToResize() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 330, y: 300), [.option]), in: context())
        #expect(step == .begin(.resize))
        #expect(gesture.state == .idle)
    }

    @Test("AC-7: サイズ変更の途中で移動の組み合わせに持ち替えると移動が始まる")
    func switchingFromResizeToMove() {
        var gesture = resizingGesture(at: CGPoint(x: 600, y: 420))
        let step = gesture.handle(sample(CGPoint(x: 610, y: 420), [.command]), in: context())
        #expect(step == .begin(.move))
    }

    @Test("AC-7: 持ち替えた先がパネルの外なら始まらない")
    func switchingOutsidePanelDoesNotStart() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 2000, y: 300), [.option]), in: context())
        #expect(step == .none)
    }

    @Test("AC-7: 設定で組み合わせを空にすると止まる")
    func emptyingSettingStops() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 330, y: 300)), in: context(move: []))
        #expect(step == .none)
        #expect(gesture.state == .idle)
    }

    @Test("AC-10: 閉じ始めたら止まる")
    func closingStops() {
        var gesture = movingGesture()
        let step = gesture.handle(sample(CGPoint(x: 330, y: 300)), in: context(isShown: false))
        #expect(step == .none)
        #expect(gesture.state == .idle)
    }

    // MARK: handle: サイドバー

    @Test("AC-10: サイドバーの開閉の動きの途中は枠を変えず、状態も変えない")
    func sidebarSlidingKeepsFrame() {
        var gesture = movingGesture()
        let before = gesture.state
        let step = gesture.handle(sample(CGPoint(x: 360, y: 300)), in: context(isSliding: true, isSidebarOpen: true))
        #expect(step == .none)
        #expect(gesture.state == before)
    }

    @Test("AC-10: 動きが終わったら今の枠と今のカーソルから続ける(幅の変化を戻さない)")
    func sidebarToggleReanchors() {
        var gesture = movingGesture()
        let wide = CGRect(x: -120, y: 100, width: 740, height: 340)
        let pointer = CGPoint(x: 360, y: 300)
        #expect(gesture.handle(sample(pointer), in: context(frame: wide, isSidebarOpen: true)) == .none)
        #expect(gesture.state == .moving(PanelPointerAnchor(frame: wide, pointer: pointer, isSidebarOpen: true)))

        let step = gesture.handle(sample(CGPoint(x: 370, y: 290)), in: context(frame: wide, isSidebarOpen: true))
        #expect(step == .setOrigin(CGPoint(x: -110, y: 90)))
    }

    @Test("AC-10: サイズ変更もサイドバーの開閉で起点を置き直し、角は変わらない")
    func sidebarToggleKeepsCorner() {
        var gesture = resizingGesture(at: CGPoint(x: 600, y: 420))
        let wide = CGRect(x: -120, y: 100, width: 740, height: 340)
        let pointer = CGPoint(x: 600, y: 420)
        #expect(gesture.handle(sample(pointer, [.option]), in: context(frame: wide, isSidebarOpen: true)) == .none)
        #expect(gesture.state == .resizing(
            PanelPointerAnchor(frame: wide, pointer: pointer, isSidebarOpen: true),
            .topRight
        ))
    }

    // MARK: PanelPointerAvailability.make

    @Test("AC-10: 表示中で動きの段階が shown のときだけ isPanelShown", arguments: [
        (true, PanelMotionPhase.shown, true),
        (true, PanelMotionPhase.opening, false),
        (true, PanelMotionPhase.closing, false),
        (true, PanelMotionPhase.hidden, false),
        (false, PanelMotionPhase.shown, false),
        (false, PanelMotionPhase.hidden, false),
    ])
    func availabilityIsPanelShown(isPresented: Bool, phase: PanelMotionPhase, expected: Bool) {
        let availability = PanelPointerAvailability.make(
            isPresented: isPresented,
            motionPhase: phase,
            isSidebarSliding: false,
            isSidebarOpen: false
        )
        #expect(availability.isPanelShown == expected)
    }

    @Test("AC-10: サイドバーの状態はそのまま渡る")
    func availabilityPassesSidebarState() {
        let availability = PanelPointerAvailability.make(
            isPresented: true,
            motionPhase: .shown,
            isSidebarSliding: true,
            isSidebarOpen: true
        )
        #expect(availability == PanelPointerAvailability(isPanelShown: true, isSidebarSliding: true, isSidebarOpen: true))
    }

    // MARK: PanelPointerStep.applying

    @Test("AC-5: 同じ枠なら none")
    func applyingSameFrame() {
        #expect(PanelPointerStep.applying(frame, to: frame) == .none)
    }

    @Test("AC-5: 大きさが同じなら setOrigin")
    func applyingSameSize() {
        let moved = frame.offsetBy(dx: 10, dy: -5)
        #expect(PanelPointerStep.applying(moved, to: frame) == .setOrigin(moved.origin))
    }

    @Test("AC-6: 大きさが違えば setFrame")
    func applyingDifferentSize() {
        let resized = CGRect(x: 100, y: 100, width: 560, height: 340)
        #expect(PanelPointerStep.applying(resized, to: frame) == .setFrame(resized))
    }
}
