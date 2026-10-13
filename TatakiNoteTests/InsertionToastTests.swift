import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class InsertionToastSpy: InsertionToastPresenting {
    private(set) var shows: [(message: String, frame: CGRect)] = []
    private(set) var dismissCount = 0

    func show(_ message: String, around panelFrame: CGRect) {
        shows.append((message, panelFrame))
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
final class ToastSleepGate {
    private(set) var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { continuations.append($0) }
    }

    func release(_ index: Int) {
        continuations[index].resume()
    }
}

@MainActor
struct InsertionToastValueTests {
    @Test("AC-9: 文は「<アプリ名> に挿入しました」「<アプリ名> に送信しました」になる")
    func messageWithAppName() {
        #expect(InsertionToast.message(appName: "Safari", didSend: false) == "Safari に挿入しました")
        #expect(InsertionToast.message(appName: "Safari", didSend: true) == "Safari に送信しました")
        #expect(InsertionToast.message(appName: " Safari ", didSend: false) == "Safari に挿入しました")
    }

    @Test("AC-9: アプリ名が無い・空・空白だけなら「挿入しました」「送信しました」になる")
    func messageWithoutAppName() {
        for name in [nil, "", "  "] as [String?] {
            #expect(InsertionToast.message(appName: name, didSend: false) == "挿入しました")
            #expect(InsertionToast.message(appName: name, didSend: true) == "送信しました")
        }
    }

    @Test("AC-9: トーストは 1.9 秒出す")
    func durationIsOnePointNineSeconds() {
        #expect(InsertionToast.duration == .milliseconds(1900))
    }

    private let toastSize = CGSize(width: 200, height: 60)
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("AC-9: パネルの中央に収まるなら、トーストはパネルの枠の中央に置く")
    func frameCentersOnPanel() {
        let panel = CGRect(x: 300, y: 300, width: 400, height: 200)

        let frame = InsertionToast.frame(toastSize: toastSize, panelFrame: panel, visibleFrame: visible)

        #expect(frame == CGRect(x: 400, y: 370, width: 200, height: 60))
    }

    @Test("AC-9: パネルが画面の端からはみ出していたら、トーストを見える範囲の内側へ寄せる")
    func frameIsPulledInsideVisibleFrame() {
        let left = CGRect(x: -300, y: 300, width: 400, height: 200)
        #expect(InsertionToast.frame(toastSize: toastSize, panelFrame: left, visibleFrame: visible).minX == 0)

        let right = CGRect(x: 900, y: 300, width: 400, height: 200)
        #expect(InsertionToast.frame(toastSize: toastSize, panelFrame: right, visibleFrame: visible).maxX == 1000)

        let bottom = CGRect(x: 300, y: -100, width: 400, height: 100)
        #expect(InsertionToast.frame(toastSize: toastSize, panelFrame: bottom, visibleFrame: visible).minY == 0)

        let top = CGRect(x: 300, y: 790, width: 400, height: 200)
        #expect(InsertionToast.frame(toastSize: toastSize, panelFrame: top, visibleFrame: visible).maxY == 800)
    }

    @Test("AC-9: トーストが見える範囲より大きければ、見える範囲の左端・下端に合わせる")
    func frameLargerThanVisibleFrameAlignsToOrigin() {
        let small = CGRect(x: 50, y: 60, width: 100, height: 40)
        let panel = CGRect(x: 300, y: 300, width: 400, height: 200)

        let frame = InsertionToast.frame(toastSize: toastSize, panelFrame: panel, visibleFrame: small)

        #expect(frame.origin == CGPoint(x: 50, y: 60))
    }

    @Test("AC-9: 見える範囲が分からなければ、パネルの中央のままにする")
    func frameWithoutVisibleFrameStaysCentered() {
        let panel = CGRect(x: -300, y: 300, width: 400, height: 200)

        let frame = InsertionToast.frame(toastSize: toastSize, panelFrame: panel, visibleFrame: nil)

        #expect(frame.midX == panel.midX)
        #expect(frame.midY == panel.midY)
    }
}

@MainActor
struct InsertionToastControllerTests {
    private final class Announcements {
        var messages: [String] = []
    }

    private func makeController(gate: ToastSleepGate, announcements: Announcements) -> InsertionToastController {
        InsertionToastController(
            sleep: { await gate.sleep($0) },
            announce: { announcements.messages.append($0) }
        )
    }

    private let panelFrame = CGRect(x: 300, y: 300, width: 400, height: 200)

    private func waitForCondition(_ condition: () -> Bool) async {
        _ = try? await waitUntil(attempts: 200, interval: .milliseconds(25), condition)
    }

    @Test("AC-9: show で窓が見えて文が入り、1.9 秒の待ちのあとに消える")
    func showsThenHidesAfterDuration() async {
        let gate = ToastSleepGate()
        let announcements = Announcements()
        let controller = makeController(gate: gate, announcements: announcements)

        controller.show("Safari に挿入しました", around: panelFrame)

        #expect(controller.message == "Safari に挿入しました")
        #expect(controller.toastWindow?.isVisible == true)
        #expect(announcements.messages == ["Safari に挿入しました"])
        await waitForCondition { gate.durations.count == 1 }
        #expect(gate.durations == [.milliseconds(1900)])

        gate.release(0)
        await waitForCondition { controller.message == nil }

        #expect(controller.message == nil)
        #expect(controller.toastWindow?.isVisible == false)
        controller.dismiss()
    }

    @Test("AC-10: 出ている間に show すると文が替わり、前の待ちが終わっても消えず、新しい待ちで消える")
    func secondShowReplacesMessageAndRestartsTimer() async {
        let gate = ToastSleepGate()
        let announcements = Announcements()
        let controller = makeController(gate: gate, announcements: announcements)

        controller.show("TextEdit に挿入しました", around: panelFrame)
        await waitForCondition { gate.durations.count == 1 }
        controller.show("TextEdit に送信しました", around: panelFrame)
        await waitForCondition { gate.durations.count == 2 }

        #expect(controller.message == "TextEdit に送信しました")
        #expect(announcements.messages == ["TextEdit に挿入しました", "TextEdit に送信しました"])

        gate.release(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.message == "TextEdit に送信しました")
        #expect(controller.toastWindow?.isVisible == true)

        gate.release(1)
        await waitForCondition { controller.message == nil }
        #expect(controller.message == nil)
        #expect(controller.toastWindow?.isVisible == false)
    }

    @Test("AC-10: dismiss ですぐ消え、その後に待ちが終わっても何も起きない")
    func dismissHidesImmediately() async {
        let gate = ToastSleepGate()
        let controller = makeController(gate: gate, announcements: Announcements())

        controller.show("TextEdit に挿入しました", around: panelFrame)
        await waitForCondition { gate.durations.count == 1 }
        controller.dismiss()

        #expect(controller.message == nil)
        #expect(controller.toastWindow?.isVisible == false)

        gate.release(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(controller.message == nil)
    }

    @Test("AC-10: 出ていないときの dismiss は何もしない")
    func dismissWhenNotShownIsHarmless() {
        let controller = makeController(gate: ToastSleepGate(), announcements: Announcements())

        controller.dismiss()

        #expect(controller.message == nil)
        #expect(controller.toastWindow == nil)
    }

    @Test("AC-11: トーストの窓はキーにもメインにもならず、クリックを受けず、出してもキーにならない")
    func windowNeverTakesFocusOrClicks() async {
        let gate = ToastSleepGate()
        let controller = makeController(gate: gate, announcements: Announcements())

        controller.show("TextEdit に挿入しました", around: panelFrame)
        let window = controller.toastWindow

        #expect(window?.canBecomeKey == false)
        #expect(window?.canBecomeMain == false)
        #expect(window?.ignoresMouseEvents == true)
        #expect(window?.isKeyWindow == false)
        #expect(window?.isVisible == true)
        #expect(window?.identifier?.rawValue == "insertionToast")
        controller.dismiss()
    }
}

@MainActor
struct PanelInsertionToastWiringTests {
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let commitAndSendKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    private let target = InsertionTarget(processIdentifier: PanelInsertionToastWiringTests.ownPid, bundleIdentifier: "com.example.TextEdit", localizedName: "TextEdit")

    private struct Fixture {
        let controller: PanelController
        let toast: InsertionToastSpy
        let inserter: InserterStub
    }

    private func withFixture(
        result: InsertionResult = .inserted,
        isTrusted: Bool = true,
        hasTarget: Bool = true,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.isPanelAnimationEnabled = false
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let toast = InsertionToastSpy()
        let inserter = InserterStub(result: result)
        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: PermissionStub(isTrusted: isTrusted),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: DraftLibrary(store: .inMemory),
            animator: FakePanelFrameAnimator(),
            shaker: PanelShakerSpy(),
            toast: toast,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        if hasTarget {
            controller.targetOverride = { target }
        } else {
            controller.isTargetLookupDisabled = true
        }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, toast: toast, inserter: inserter))
    }

    private func settle(_ inserter: InserterStub) async {
        await yieldUntil { !inserter.calls.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("AC-9: 確定キーで挿入できると「<名前> に挿入しました」が、閉じる前のパネルの枠と一緒に 1 回渡る")
    func insertShowsToastWithPanelFrame() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"
            let frame = fixture.controller.panel.frame

            #expect(fixture.controller.handleKey(Self.commitKey))
            await yieldUntil { !fixture.toast.shows.isEmpty }

            #expect(fixture.toast.shows.count == 1)
            #expect(fixture.toast.shows.first?.message == "TextEdit に挿入しました")
            #expect(fixture.toast.shows.first?.frame == frame)
            #expect(!fixture.controller.model.isPresented)
        }
    }

    @Test("AC-9: 確定+送信キーで挿入できると「<名前> に送信しました」が渡る")
    func sendShowsToastWithSendMessage() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitAndSendKey))
            await yieldUntil { !fixture.toast.shows.isEmpty }

            #expect(fixture.toast.shows.map(\.message) == ["TextEdit に送信しました"])
        }
    }

    @Test("AC-9: 下の帯のボタンからの確定でもトーストが渡る")
    func buttonCommitShowsToast() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: true)
            await yieldUntil { !fixture.toast.shows.isEmpty }

            #expect(fixture.toast.shows.map(\.message) == ["TextEdit に送信しました"])
        }
    }

    @Test("AC-10: 前面にできなくて挿入されなかったときは、トーストを出さずにパネルを開き直す")
    func notInsertedShowsNoToast() async throws {
        try await withFixture(result: .targetNotActivated) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            await settle(fixture.inserter)

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.toast.shows.isEmpty)
            #expect(fixture.controller.model.isPresented)
        }
    }

    @Test("AC-10: 入力欄でなくて挿入されなかったときも、トーストを出さない")
    func noTextInputShowsNoToast() async throws {
        try await withFixture(result: .noTextInput) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            await settle(fixture.inserter)

            #expect(fixture.toast.shows.isEmpty)
        }
    }

    @Test("AC-10: 本文が空の確定ではトーストを出さない")
    func emptyTextShowsNoToast() async throws {
        try await withFixture { fixture in
            fixture.controller.open()

            #expect(fixture.controller.handleKey(Self.commitKey))
            try? await Task.sleep(for: .milliseconds(50))

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.toast.shows.isEmpty)
        }
    }

    @Test("AC-10: 挿入先なしの確定ではトーストを出さない")
    func noTargetShowsNoToast() async throws {
        try await withFixture(hasTarget: false) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            try? await Task.sleep(for: .milliseconds(50))

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.toast.shows.isEmpty)
        }
    }

    @Test("AC-10: 権限なしの確定ではトーストを出さない")
    func permissionDeniedShowsNoToast() async throws {
        try await withFixture(isTrusted: false) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            try? await Task.sleep(for: .milliseconds(50))

            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.toast.shows.isEmpty)
            #expect(!fixture.controller.model.isPresented)
        }
    }

    @Test("AC-10: パネルを開くたびに、出ているトーストを消す")
    func openDismissesToast() async throws {
        try await withFixture { fixture in
            #expect(fixture.toast.dismissCount == 0)

            fixture.controller.open()
            #expect(fixture.toast.dismissCount == 1)

            fixture.controller.close()
            fixture.controller.open()
            #expect(fixture.toast.dismissCount == 2)
        }
    }
}
