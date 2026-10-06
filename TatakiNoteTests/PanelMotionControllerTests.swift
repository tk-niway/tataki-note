import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class FakePanelFrameAnimator: PanelFrameAnimating {
    struct Call {
        let window: NSWindow
        let frame: NSRect
        let duration: TimeInterval
        let curve: PanelMotionCurve
        let windowFrame: NSRect
        let canBecomeKey: Bool
        let ignoresMouseEvents: Bool
        let isVisible: Bool
    }

    private(set) var calls: [Call] = []
    private(set) var jumps: [NSRect] = []
    private var completions: [(() -> Void)?] = []
    var completesPendingOnJump = false

    func animate(_ window: NSWindow, to frame: NSRect, duration: TimeInterval, curve: PanelMotionCurve, completion: @escaping () -> Void) {
        calls.append(
            Call(
                window: window,
                frame: frame,
                duration: duration,
                curve: curve,
                windowFrame: window.frame,
                canBecomeKey: window.canBecomeKey,
                ignoresMouseEvents: window.ignoresMouseEvents,
                isVisible: window.isVisible
            )
        )
        completions.append(completion)
    }

    func jump(_ window: NSWindow, to frame: NSRect) {
        jumps.append(frame)
        if completesPendingOnJump {
            for index in completions.indices {
                guard let completion = completions[index] else { continue }
                completions[index] = nil
                completion()
            }
        }
        window.setFrame(frame, display: false)
    }

    func finish(_ index: Int, moving: Bool = true) {
        guard completions.indices.contains(index), let completion = completions[index] else { return }
        completions[index] = nil
        if moving {
            calls[index].window.setFrame(calls[index].frame, display: false)
        }
        completion()
    }

    func isFinished(_ index: Int) -> Bool {
        completions.indices.contains(index) && completions[index] == nil
    }
}

@MainActor
final class HideApplicationCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

enum PanelMotionOpenWay: CaseIterable, Sendable {
    case hotkey
    case menu
    case autoShow
}

enum PanelMotionCloseWay: CaseIterable, Sendable {
    case escape
    case hotkey
    case closeButton
    case commit
    case commitAndSend
}

@MainActor
struct PanelMotionControllerTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: PanelMotionControllerTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let defaultSize = CGSize(width: 600, height: 400)

    private struct Fixture {
        let controller: PanelController
        let animator: FakePanelFrameAnimator
        let settings: AppSettings
        let inserter: InserterStub
        let hides: HideApplicationCounter
    }

    private func withFixture(
        animationEnabled: Bool = true,
        completesPendingOnJump: Bool = false,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.panelDefaultWidth = 600
        settings.panelDefaultHeight = 400
        settings.isPanelAnimationEnabled = animationEnabled
        let animator = FakePanelFrameAnimator()
        animator.completesPendingOnJump = completesPendingOnJump
        let inserter = InserterStub(result: .inserted)
        let hides = HideApplicationCounter()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: PermissionStub(isTrusted: true),
            notifier: NotifierStub(),
            fieldProbe: FocusedElementProbeStub(),
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            animator: animator,
            hideApplication: { hides.record() }
        )
        controller.targetOverride = { own }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, animator: animator, settings: settings, inserter: inserter, hides: hides))
    }

    private func commandH(in panel: NSPanel) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "h",
                charactersIgnoringModifiers: "h",
                isARepeat: false,
                keyCode: 4
            )
        )
    }

    private func expectedOpenFrame(size: CGSize) -> CGRect? {
        NSScreen.screens.first.map { PanelPlacement.centeredFrame(size: size, in: $0.visibleFrame) }
    }

    private func open(_ way: PanelMotionOpenWay, _ controller: PanelController) {
        switch way {
        case .hotkey:
            controller.toggle()
        case .menu:
            controller.open()
        case .autoShow:
            let probe = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
            controller.open(observedFocus: ObservedFocus(processIdentifier: 1, probe: probe))
        }
    }

    private func close(_ way: PanelMotionCloseWay, _ controller: PanelController) {
        switch way {
        case .escape:
            _ = controller.handleKey(PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false))
        case .hotkey:
            controller.toggle()
        case .closeButton:
            controller.closeFromButton()
        case .commit:
            controller.commit()
        case .commitAndSend:
            controller.commit(shouldSendAfterInsert: true)
        }
    }

    private func waitForInsertion(_ inserter: InserterStub) async {
        for _ in 0..<100 where inserter.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openAndSettle(_ fixture: Fixture) {
        fixture.controller.open()
        fixture.animator.finish(fixture.animator.calls.count - 1)
    }

    // MARK: - 開く

    @Test("AC-6: アニメーションがオンで閉じたパネルを開くと、線の枠で前に出て、本来の枠へ 0.2 秒で広げる動きが1回始まり、終わると本来の枠になる", arguments: PanelMotionOpenWay.allCases)
    func openStartsExpandingMotion(way: PanelMotionOpenWay) async throws {
        try await withFixture { fixture in
            open(way, fixture.controller)

            #expect(fixture.animator.calls.count == 1)
            let call = try #require(fixture.animator.calls.first)
            #expect(call.duration == 0.2)
            #expect(call.curve == .easeOut)
            #expect(call.window === fixture.controller.panel)
            #expect(call.windowFrame == PanelMotion.lineFrame(of: call.frame))
            #expect(call.isVisible)
            if let expected = expectedOpenFrame(size: defaultSize) {
                #expect(call.frame == expected)
            }
            #expect(fixture.controller.model.isPresented)

            fixture.animator.finish(0)

            #expect(fixture.controller.panel.frame == call.frame)
            #expect(fixture.controller.panel.isVisible)
            #expect(fixture.controller.panel.canBecomeKey)
            #expect(fixture.controller.panel.contentMinSize == CGSize(width: 320, height: 160))
        }
    }

    @Test("AC-6: 開いている間にもう一度開いても、動きは始め直さない")
    func openWhilePresentedDoesNotRestartMotion() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.animator.finish(0)

            fixture.controller.open()

            #expect(fixture.animator.calls.count == 1)
            #expect(fixture.controller.panel.isVisible)
        }
    }

    @Test("AC-7: 開く動きの途中でも、パネルは key になれる状態で前に出て、マウスも受け付け、入力した文字は動きの終わりの後も残る")
    func panelAcceptsInputWhileOpening() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller

            controller.open()

            let call = try #require(fixture.animator.calls.first)
            #expect(call.canBecomeKey)
            #expect(call.ignoresMouseEvents == false)
            #expect(call.isVisible)
            #expect(controller.panel.canBecomeKey)
            #expect(controller.panel.ignoresMouseEvents == false)
            #expect(controller.model.focusRequest == 1)
            #expect(controller.windowWillResize(controller.panel, to: NSSize(width: 10, height: 2)) == NSSize(width: 10, height: 2))

            controller.model.text = "abc"
            #expect(fixture.animator.isFinished(0) == false)
            fixture.animator.finish(0)

            #expect(controller.model.text == "abc")
            #expect(controller.panel.canBecomeKey)
            #expect(controller.panel.ignoresMouseEvents == false)
            #expect(controller.windowWillResize(controller.panel, to: NSSize(width: 10, height: 2)) == NSSize(width: 320, height: 160))
        }
    }

    // MARK: - 閉じる

    @Test("AC-8: アニメーションがオンで開いたパネルを閉じると、閉じた状態に即座になり、本物のパネルはすぐ隠れ、見た目を写した窓が key にもマウスにも反応せず線へ縮み、終わると写した窓が消える", arguments: PanelMotionCloseWay.allCases)
    func closeStartsShrinkingMotion(way: PanelMotionCloseWay) async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            let moved = panel.frame.offsetBy(dx: 12, dy: -8)
            panel.setFrame(moved, display: false)
            controller.model.text = "abc"

            close(way, controller)

            #expect(controller.model.isPresented == false)
            #expect(fixture.animator.calls.count == 2)
            let call = fixture.animator.calls[1]
            let ghost = call.window
            #expect(call.duration == 0.2)
            #expect(call.curve == .easeIn)
            #expect(ghost !== panel)
            #expect(call.windowFrame == moved)
            #expect(call.frame == PanelMotion.lineFrame(of: moved))
            #expect(call.canBecomeKey == false)
            #expect(call.ignoresMouseEvents)
            #expect(call.isVisible)
            #expect(panel.isVisible == false)
            #expect(panel.frame == moved)
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)
            #expect(panel.contentMinSize == CGSize(width: 320, height: 160))
            #expect(controller.windowWillResize(panel, to: NSSize(width: 10, height: 2)) == NSSize(width: 320, height: 160))

            fixture.animator.finish(1)

            #expect(ghost.isVisible == false)
            #expect(panel.isVisible == false)
            #expect(panel.frame == moved)
            #expect(panel.canBecomeKey)
            #expect(controller.model.isPresented == false)
        }
    }

    @Test("AC-9: 確定+挿入・確定+送信で閉じるとき、閉じる動きの終わりの知らせより前に挿入が始まる", arguments: [false, true])
    func commitInsertsWithoutWaitingForMotion(shouldSend: Bool) async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            openAndSettle(fixture)
            controller.model.text = "abc"
            var motionStartedAtRequest: Int?
            var wasFinishedAtRequest: Bool?
            var panelWasVisibleAtRequest: Bool?
            controller.onInsertionRequested = { _, _, _ in
                motionStartedAtRequest = fixture.animator.calls.count
                wasFinishedAtRequest = fixture.animator.isFinished(1)
                panelWasVisibleAtRequest = controller.panel.isVisible
            }

            controller.commit(shouldSendAfterInsert: shouldSend)
            await waitForInsertion(fixture.inserter)

            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.animator.isFinished(1) == false)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "abc")
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
            #expect(motionStartedAtRequest == 2)
            #expect(wasFinishedAtRequest == false)
            #expect(panelWasVisibleAtRequest == false)
            #expect(controller.panel.isVisible == false)
            #expect(fixture.animator.calls[1].window.isVisible)

            fixture.animator.finish(1)
            #expect(controller.panel.isVisible == false)
            #expect(fixture.animator.calls[1].window.isVisible == false)
        }
    }

    // MARK: - 動きの途中の開閉

    @Test("AC-10: 閉じる動きの途中に開くと開く動きになり、古い閉じる動きの終わりの知らせが来てもパネルは隠れない", arguments: [false, true])
    func reopenDuringClosingIgnoresStaleCompletion(completesPendingOnJump: Bool) async throws {
        try await withFixture(completesPendingOnJump: completesPendingOnJump) { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            controller.toggle()
            #expect(fixture.animator.calls.count == 2)
            #expect(controller.model.isPresented == false)
            #expect(panel.isVisible == false)
            #expect(fixture.animator.calls[1].window.isVisible)

            controller.toggle()

            #expect(controller.model.isPresented)
            #expect(fixture.animator.calls.count == 3)
            #expect(fixture.animator.calls[1].window.isVisible == false)
            let call = fixture.animator.calls[2]
            #expect(call.canBecomeKey)
            #expect(call.ignoresMouseEvents == false)
            #expect(call.isVisible)
            #expect(call.curve == .easeOut)
            #expect(call.windowFrame == PanelMotion.lineFrame(of: call.frame))
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)

            fixture.animator.finish(1, moving: false)

            #expect(panel.isVisible)
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)
            #expect(controller.model.isPresented)

            fixture.animator.finish(2)

            #expect(panel.frame == call.frame)
            #expect(panel.isVisible)
            #expect(panel.canBecomeKey)
        }
    }

    @Test("AC-10: 開く動きの途中に閉じると、本物のパネルはすぐ隠れて行き先の枠に戻り、そこの線へ写した窓が縮む", arguments: [false, true])
    func closeDuringOpeningShrinksFromDestination(completesPendingOnJump: Bool) async throws {
        try await withFixture(completesPendingOnJump: completesPendingOnJump) { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.toggle()
            let destination = fixture.animator.calls[0].frame
            #expect(panel.frame == PanelMotion.lineFrame(of: destination))

            controller.toggle()

            #expect(fixture.animator.calls.count == 2)
            let call = fixture.animator.calls[1]
            #expect(call.curve == .easeIn)
            #expect(call.frame == PanelMotion.lineFrame(of: destination))
            #expect(call.canBecomeKey == false)
            #expect(call.ignoresMouseEvents)
            #expect(call.isVisible)
            #expect(panel.isVisible == false)
            #expect(panel.frame == destination)
            #expect(fixture.animator.jumps == [destination])
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)

            fixture.animator.finish(0, moving: false)
            #expect(panel.isVisible == false)
            #expect(call.window.isVisible)

            fixture.animator.finish(1)

            #expect(call.window.isVisible == false)
            #expect(panel.isVisible == false)
            #expect(panel.frame == destination)
        }
    }

    @Test("AC-10: 閉じる動きの途中にもう一度閉じても新しい動きは始まらず、閉じ終わると閉じ始めの枠に戻る")
    func closeDuringClosingKeepsOriginalMotion() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            let moved = panel.frame.offsetBy(dx: -20, dy: 14)
            panel.setFrame(moved, display: false)

            controller.close()
            controller.close()

            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.animator.jumps.isEmpty)
            #expect(fixture.animator.calls[1].frame == PanelMotion.lineFrame(of: moved))
            #expect(fixture.animator.calls[1].window.isVisible)

            fixture.animator.finish(1)

            #expect(fixture.animator.calls[1].window.isVisible == false)
            #expect(panel.isVisible == false)
            #expect(panel.frame == moved)
        }
    }

    // MARK: - アニメーションがオフ

    @Test("AC-11: アニメーションがオフのときは、動きを始めずに本来の枠で key になれる状態で開き、閉じるとすぐ隠れる")
    func disabledAnimationOpensAndClosesImmediately() async throws {
        try await withFixture(animationEnabled: false) { fixture in
            let controller = fixture.controller
            let panel = controller.panel

            controller.toggle()

            #expect(fixture.animator.calls.isEmpty)
            #expect(panel.canBecomeKey)
            #expect(panel.isVisible)
            #expect(panel.ignoresMouseEvents == false)
            if let expected = expectedOpenFrame(size: defaultSize) {
                #expect(panel.frame == expected)
            }

            controller.toggle()

            #expect(fixture.animator.calls.isEmpty)
            #expect(panel.isVisible == false)
            #expect(panel.canBecomeKey)
            #expect(controller.model.isPresented == false)
        }
    }

    @Test("AC-11: アニメーションがオフのとき、esc・× ボタン・確定+挿入のどれでも動きを始めずにすぐ隠れる")
    func disabledAnimationClosesImmediatelyForEveryWay() async throws {
        for way in PanelMotionCloseWay.allCases {
            try await withFixture(animationEnabled: false) { fixture in
                let controller = fixture.controller
                controller.open()
                controller.model.text = "abc"

                close(way, controller)

                #expect(fixture.animator.calls.isEmpty)
                #expect(controller.panel.isVisible == false)
                #expect(controller.model.isPresented == false)
            }
        }
    }

    @Test("AC-11: 閉じる動きの途中にオフにして開いても、線の枠でなく開く場所の計算どおりの枠で、key になれる状態で前に出る")
    func disablingDuringClosingOpensAtRestingFrame() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            let rest = fixture.animator.calls[0].frame
            controller.toggle()
            #expect(fixture.animator.calls.count == 2)
            #expect(panel.isVisible == false)
            fixture.settings.isPanelAnimationEnabled = false

            controller.toggle()

            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.animator.calls[1].window.isVisible == false)
            #expect(panel.frame == rest)
            #expect(panel.isVisible)
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)
            #expect(controller.model.isPresented)

            fixture.animator.finish(1, moving: false)

            #expect(panel.isVisible)
            #expect(panel.frame == rest)
        }
    }

    @Test("AC-11: 開く動きの途中にオフにして閉じると、すぐ隠れて枠は行き先の枠に戻る")
    func disablingDuringOpeningClosesAtDestination() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.toggle()
            let destination = fixture.animator.calls[0].frame
            fixture.settings.isPanelAnimationEnabled = false

            controller.toggle()

            #expect(fixture.animator.calls.count == 1)
            #expect(panel.isVisible == false)
            #expect(fixture.animator.jumps == [destination])
            #expect(panel.frame == destination)
            #expect(panel.canBecomeKey)
            #expect(panel.contentMinSize == CGSize(width: 320, height: 160))
        }
    }

    // MARK: - 大きさ

    @Test("AC-19: 開くときの大きさは設定の既定の大きさで、ドラッグで決めた大きさは開閉の動きの後も保たれ、次に開くときもその大きさになる")
    func motionKeepsPanelSizes() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel

            controller.open()
            let firstTarget = fixture.animator.calls[0].frame
            fixture.animator.finish(0)
            #expect(firstTarget.size == (expectedOpenFrame(size: defaultSize)?.size ?? firstTarget.size))
            #expect(controller.heldPanelSize == nil)

            controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
            let dragged = NSRect(origin: panel.frame.origin, size: CGSize(width: 700, height: 500))
            panel.setFrame(dragged, display: false)
            controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
            let heldSize = try #require(controller.heldPanelSize)

            controller.close()
            #expect(controller.heldPanelSize == heldSize)
            #expect(fixture.animator.calls[1].frame.width == dragged.width)
            #expect(PanelMotion.lineFrame(of: dragged).size == CGSize(width: dragged.width, height: 2))
            fixture.animator.finish(1)

            #expect(controller.heldPanelSize == heldSize)
            #expect(panel.frame.size == dragged.size)

            controller.open()
            #expect(fixture.animator.calls[2].frame.size == heldSize)
            fixture.animator.finish(2)
            #expect(controller.heldPanelSize == heldSize)
            #expect(panel.frame.size == heldSize)
        }
    }

    // MARK: - ⌘H

    @Test("AC-12: アニメーションがオンで開いているときの ⌘H は、パネルが処理して閉じる動きを始め、動きの終わりにアプリを隠す")
    func hideKeyClosesThenHidesApplication() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)

            let handled = panel.performKeyEquivalent(with: try commandH(in: panel))

            #expect(handled)
            #expect(controller.model.isPresented == false)
            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.animator.calls[1].curve == .easeIn)
            #expect(fixture.animator.calls[1].canBecomeKey == false)
            #expect(panel.isVisible == false)
            #expect(fixture.animator.calls[1].window.isVisible)
            #expect(fixture.hides.count == 0)

            fixture.animator.finish(1)

            #expect(panel.isVisible == false)
            #expect(fixture.hides.count == 1)
        }
    }

    @Test("AC-12: 開く動きの途中の ⌘H も、行き先の枠から閉じる動きにして、動きの終わりにアプリを隠す")
    func hideKeyDuringOpeningClosesThenHidesApplication() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.open()
            let destination = fixture.animator.calls[0].frame

            let handled = panel.performKeyEquivalent(with: try commandH(in: panel))

            #expect(handled)
            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.animator.calls[1].frame == PanelMotion.lineFrame(of: destination))
            #expect(fixture.hides.count == 0)

            fixture.animator.finish(0, moving: false)
            #expect(fixture.hides.count == 0)

            fixture.animator.finish(1)

            #expect(panel.isVisible == false)
            #expect(panel.frame == destination)
            #expect(fixture.hides.count == 1)
        }
    }

    @Test("AC-12: ⌘H の閉じる動きの途中で開き直すと、古い終わりの知らせが同期で来ても後から来ても、アプリは隠さず、パネルは開いたまま", arguments: [false, true])
    func reopenDuringHideKeyClosingDoesNotHideApplication(completesPendingOnJump: Bool) async throws {
        try await withFixture(completesPendingOnJump: completesPendingOnJump) { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            _ = panel.performKeyEquivalent(with: try commandH(in: panel))
            #expect(fixture.animator.calls.count == 2)

            controller.open()

            #expect(fixture.animator.calls.count == 3)
            #expect(fixture.hides.count == 0)
            #expect(controller.model.isPresented)

            fixture.animator.finish(1, moving: false)

            #expect(fixture.hides.count == 0)
            #expect(panel.isVisible)
            #expect(panel.canBecomeKey)
            #expect(controller.model.isPresented)

            fixture.animator.finish(2)

            #expect(fixture.hides.count == 0)
            #expect(panel.isVisible)
            #expect(controller.model.isPresented)
        }
    }

    @Test("AC-13: アニメーションがオフのときの ⌘H は、パネルが処理せず標準の「隠す」に渡る")
    func hideKeyIsNotHandledWhenAnimationIsOff() async throws {
        try await withFixture(animationEnabled: false) { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.open()

            let handled = panel.performKeyEquivalent(with: try commandH(in: panel))

            #expect(handled == false)
            #expect(controller.handleHideKey() == false)
            #expect(fixture.animator.calls.isEmpty)
            #expect(fixture.hides.count == 0)
            #expect(controller.model.isPresented)
            #expect(panel.isVisible)
        }
    }

    @Test("AC-13: 閉じる動きの途中・閉じているときの ⌘H は、パネルが処理せず標準の「隠す」に渡る")
    func hideKeyIsNotHandledWhileClosingOrClosed() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel

            let handledWhileClosed = panel.performKeyEquivalent(with: try commandH(in: panel))
            #expect(handledWhileClosed == false)
            #expect(fixture.animator.calls.isEmpty)

            openAndSettle(fixture)
            controller.close()
            #expect(fixture.animator.calls.count == 2)

            let handledWhileClosing = panel.performKeyEquivalent(with: try commandH(in: panel))

            #expect(handledWhileClosing == false)
            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.hides.count == 0)

            fixture.animator.finish(1)

            #expect(fixture.hides.count == 0)
            #expect(panel.isVisible == false)
        }
    }

    // MARK: - アプリが隠れたとき

    @Test("AC-15: アプリが隠れたときは、閉じる動きの途中でも動きなしで隠して閉じた状態にし、枠を閉じ始めの枠に戻し、後から終わりの知らせが来ても何もしない")
    func closeImmediatelyDuringClosing() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            let moved = panel.frame.offsetBy(dx: 16, dy: -10)
            panel.setFrame(moved, display: false)
            controller.close()
            let ghost = fixture.animator.calls[1].window
            #expect(ghost.isVisible)
            #expect(panel.isVisible == false)

            controller.closeImmediately()

            #expect(ghost.isVisible == false)
            #expect(panel.isVisible == false)
            #expect(panel.frame == moved)
            #expect(fixture.animator.jumps.isEmpty)
            #expect(panel.canBecomeKey)
            #expect(panel.ignoresMouseEvents == false)
            #expect(panel.contentMinSize == CGSize(width: 320, height: 160))
            #expect(controller.model.isPresented == false)

            fixture.animator.finish(1, moving: false)

            #expect(panel.isVisible == false)
            #expect(panel.frame == moved)
            #expect(fixture.animator.calls.count == 2)
            #expect(fixture.hides.count == 0)
        }
    }

    @Test("AC-15: アプリが隠れたときに開く動きの途中なら、動きなしで隠して枠を行き先の枠に戻す")
    func closeImmediatelyDuringOpening() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.open()
            let destination = fixture.animator.calls[0].frame
            #expect(panel.frame == PanelMotion.lineFrame(of: destination))

            controller.closeImmediately()

            #expect(panel.isVisible == false)
            #expect(panel.frame == destination)
            #expect(fixture.animator.jumps == [destination])
            #expect(controller.model.isPresented == false)

            fixture.animator.finish(0, moving: false)

            #expect(panel.isVisible == false)
            #expect(panel.frame == destination)
        }
    }

    @Test("AC-15: アプリが隠れたときに開き終わっていれば、動きなしで隠して閉じた状態にする", arguments: [false, true])
    func closeImmediatelyWhenShown(animationEnabled: Bool) async throws {
        try await withFixture(animationEnabled: animationEnabled) { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            controller.open()
            if animationEnabled {
                fixture.animator.finish(0)
            }
            let frame = panel.frame

            controller.closeImmediately()

            #expect(panel.isVisible == false)
            #expect(panel.frame == frame)
            #expect(controller.model.isPresented == false)
            #expect(fixture.animator.calls.count == (animationEnabled ? 1 : 0))
            #expect(panel.canBecomeKey)
        }
    }

    @Test("AC-15: ⌘H の閉じる動きの途中にアプリが隠れたときも、動きなしで閉じ、終わりの知らせでアプリをもう一度隠さない")
    func closeImmediatelyAfterHideKeyDoesNotHideAgain() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            let frame = panel.frame
            _ = panel.performKeyEquivalent(with: try commandH(in: panel))

            controller.closeImmediately()
            fixture.animator.finish(1, moving: false)

            #expect(panel.isVisible == false)
            #expect(panel.frame == frame)
            #expect(fixture.hides.count == 0)
        }
    }

    @Test("AC-19: 閉じる動きの間に枠が線になっても、保っている大きさは変わらない")
    func closingMotionDoesNotChangeHeldSize() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let panel = controller.panel
            openAndSettle(fixture)
            #expect(controller.heldPanelSize == nil)

            controller.close()
            fixture.animator.finish(1)

            #expect(controller.heldPanelSize == nil)
            #expect(panel.frame.size == fixture.animator.calls[0].frame.size)
        }
    }
}
