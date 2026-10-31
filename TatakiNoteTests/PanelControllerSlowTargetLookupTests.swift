import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class SlowLookupFixture {
    static let ownPid: pid_t = 4242
    static let editor = WatcherFixture.editor
    static let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    static let element = AXUIElementCreateApplication(pid_t.max)
    static let fieldFrame = CGRect(x: 100, y: 100, width: 200, height: 40)

    let controller: PanelController
    let lookup: ControlledOpeningTargetLookup
    let fieldProbe: PerAppProbeStub
    let lookupProbe: PerAppProbeStub
    let animator = FakePanelFrameAnimator()
    let inserter = InserterStub(result: .inserted)
    private let monitorBox = MonitorBox()

    var outlineRect: CGRect? { monitorBox.monitor?.outline.rect }

    init(settings: AppSettings, isRunning: Bool) {
        let fieldProbe = PerAppProbeStub()
        fieldProbe.elementFrame = Self.fieldFrame
        let lookupProbe = PerAppProbeStub()
        lookupProbe.results[Self.editor.processIdentifier] = FocusedElementProbe(
            element: Self.element,
            lookup: WatcherFixture.textFieldLookup,
            frame: Self.fieldFrame
        )
        let lookup = ControlledOpeningTargetLookup(probe: lookupProbe)
        let box = monitorBox
        let editorWindow = OnScreenWindow(
            processIdentifier: Self.editor.processIdentifier,
            layer: 0,
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        self.fieldProbe = fieldProbe
        self.lookupProbe = lookupProbe
        self.lookup = lookup
        self.controller = PanelControllerFactory.make(
            settings: settings,
            probe: fieldProbe,
            inserter: inserter,
            permission: PermissionStub(isTrusted: true),
            openingLookup: lookup,
            ownProcessIdentifier: Self.ownPid,
            animator: animator,
            makeTargetMonitor: { model in
                let monitor = InsertionTargetMonitor(
                    panelModel: model,
                    probe: fieldProbe,
                    ownProcessIdentifier: Self.ownPid,
                    exposeWebContent: { _ in },
                    isOutlineEnabled: { true },
                    frontmostApplication: { nil },
                    isRunning: { _ in isRunning },
                    onScreenWindows: { [editorWindow] },
                    mouseLocation: { .zero },
                    sleep: { _ in },
                    pollsAutomatically: false,
                    addClickMonitor: { _ in nil },
                    removeClickMonitor: { _ in }
                )
                box.monitor = monitor
                return monitor
            }
        )
    }

    func use(_ target: InsertionTarget?) {
        controller.targetOverride = { target }
    }
}

@MainActor
struct PanelControllerSlowTargetLookupTests {
    private let editor = SlowLookupFixture.editor
    private let own = SlowLookupFixture.own
    private let fieldFrame = SlowLookupFixture.fieldFrame

    private func withFixture(
        mode: PanelScreen = .main,
        isAnimationEnabled: Bool = false,
        isRunning: Bool = true,
        _ body: (SlowLookupFixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = mode
        settings.isInsertionTargetOutlineShown = true
        settings.animationMode = isAnimationEnabled ? .on : .off
        let fixture = SlowLookupFixture(settings: settings, isRunning: isRunning)
        defer { fixture.controller.panel.orderOut(nil) }
        try await body(fixture)
    }

    private func observedFocus(frame: CGRect?) -> ObservedFocus {
        ObservedFocus(
            processIdentifier: editor.processIdentifier,
            probe: FocusedElementProbe(element: SlowLookupFixture.element, lookup: WatcherFixture.textFieldLookup, frame: frame)
        )
    }

    // MARK: - AC-1

    @Test("AC-1: 調べが締め切りまでに終わるときは、開いた時点で挿入先と枠線が決まり、待ちの印は立たない")
    func finishedLookupDecidesTargetAtOpen() async throws {
        try await withFixture(mode: .nearFocusedField) { fixture in
            fixture.use(editor)

            fixture.controller.open()

            let model = fixture.controller.model
            #expect(model.isPresented)
            #expect(model.target == editor)
            #expect(!model.isTargetPending)
            #expect(model.pendingLookupApp == nil)
            #expect(fixture.outlineRect == fieldFrame)
            #expect(fixture.lookup.requests.count == 1)
            #expect(fixture.lookupProbe.targets == [editor])
            #expect(fixture.fieldProbe.targets.isEmpty)
            #expect(fixture.fieldProbe.frameRequests.isEmpty)
        }
    }

    @Test("AC-1: 自分自身・挿入先なし・止まったアプリ・挿入先を探さない開き方では、開くときの調べを使わない")
    func lookupIsNotUsedWithoutAnotherRunningApp() async throws {
        try await withFixture { fixture in
            fixture.use(own)
            fixture.controller.open()
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.target == own)
            #expect(fixture.lookup.requests.isEmpty)
        }
        try await withFixture { fixture in
            fixture.use(editor)
            fixture.controller.isTargetLookupDisabled = true
            fixture.controller.open()
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.target == nil)
            #expect(fixture.lookup.requests.isEmpty)
        }
        try await withFixture { fixture in
            fixture.use(editor)
            fixture.controller.openWithoutTarget()
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.target == nil)
            #expect(fixture.lookup.requests.isEmpty)
        }
        try await withFixture(isRunning: false) { fixture in
            fixture.use(editor)
            fixture.controller.open()
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.target == nil)
            #expect(!fixture.controller.model.isTargetPending)
            #expect(fixture.lookup.requests.isEmpty)
        }
    }

    // MARK: - AC-2

    @Test("AC-2: 調べが締め切りを超えると、答えを待たずにパネルが開き、待ちの印が立って挿入先も枠線も無い")
    func slowLookupOpensPanelWithoutWaiting() async throws {
        try await withFixture { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)

            fixture.controller.open()

            let model = fixture.controller.model
            #expect(model.isPresented)
            #expect(model.isTargetPending)
            #expect(model.pendingLookupApp == editor)
            #expect(model.target == nil)
            #expect(fixture.outlineRect == nil)
        }
    }

    @Test("AC-2: 自動表示の見張りの結果つきで開くときも、締め切りを超えれば先に開く")
    func slowLookupOpensPanelWithObservedFocus() async throws {
        try await withFixture { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)

            fixture.controller.open(observedFocus: observedFocus(frame: fieldFrame))

            let model = fixture.controller.model
            #expect(fixture.lookup.requests.first?.observedProbe?.frame == fieldFrame)
            #expect(model.isPresented)
            #expect(model.isTargetPending)
            #expect(model.pendingLookupApp == editor)
            #expect(model.target == nil)
            #expect(fixture.outlineRect == nil)
        }
    }

    // MARK: - AC-3

    @Test("AC-3: 「入力欄の近く」で先に出すときは、入力欄の位置を問い合わせない")
    func slowOpenDoesNotQueryFieldFrame() async throws {
        try await withFixture(mode: .nearFocusedField) { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)

            fixture.controller.open()

            #expect(fixture.controller.model.isPresented)
            #expect(fixture.fieldProbe.targets.isEmpty)
            #expect(fixture.fieldProbe.frameRequests.isEmpty)
        }
    }

    @Test("AC-3: 見張りの結果に枠が無くても、先に出すときは入力欄の位置を問い合わせない")
    func slowOpenWithObservedFocusWithoutFrameDoesNotQuery() async throws {
        try await withFixture(mode: .nearFocusedField) { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)

            fixture.controller.open(observedFocus: observedFocus(frame: nil))

            #expect(fixture.controller.model.isPresented)
            #expect(fixture.fieldProbe.targets.isEmpty)
            #expect(fixture.fieldProbe.frameRequests.isEmpty)
        }
    }

    // MARK: - AC-5

    @Test("AC-5: 先に出した後に入力欄の答えが届くと、挿入先と枠線が決まり、待ちの印が消え、パネルの枠は変わらない")
    func lateFieldAnswerDecidesTargetWithoutMovingPanel() async throws {
        try await withFixture(mode: .nearFocusedField) { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)
            fixture.controller.open()
            let frameBefore = fixture.controller.panel.frame

            fixture.lookup.finishAll()

            let model = fixture.controller.model
            #expect(model.target == editor)
            #expect(!model.isTargetPending)
            #expect(model.pendingLookupApp == nil)
            #expect(fixture.outlineRect == fieldFrame)
            #expect(fixture.controller.panel.frame == frameBefore)
        }
    }

    @Test("AC-5: 先に出した後に入力欄でない答えが届くと、挿入先なしのまま待ちの印が消え、パネルの枠は変わらない")
    func lateNonFieldAnswerLeavesNoTarget() async throws {
        try await withFixture(mode: .nearFocusedField) { fixture in
            fixture.lookupProbe.results[editor.processIdentifier] = FocusedElementProbe(
                element: SlowLookupFixture.element,
                lookup: WatcherFixture.buttonLookup,
                frame: nil
            )
            fixture.lookup.respondsLate = true
            fixture.use(editor)
            fixture.controller.open()
            let frameBefore = fixture.controller.panel.frame

            fixture.lookup.finishAll()

            let model = fixture.controller.model
            #expect(model.target == nil)
            #expect(!model.isTargetPending)
            #expect(model.pendingLookupApp == nil)
            #expect(fixture.outlineRect == nil)
            #expect(fixture.controller.panel.frame == frameBefore)
        }
    }

    // MARK: - AC-7

    @Test("AC-7: 待ちの間に確定すると、閉じず挿入せず文章が残り、「挿入先なし」の合図が増える。答えが届いた後の確定で挿入する")
    func commitWhilePendingKeepsTextThenInsertsAfterAnswer() async throws {
        try await withFixture { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)
            fixture.controller.open()
            let model = fixture.controller.model
            model.text = "hello"
            let alertsBefore = model.noTargetAlertCount

            fixture.controller.commit()

            #expect(model.isPresented)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(model.text == "hello")
            #expect(model.noTargetAlertCount == alertsBefore + 1)
            #expect(!model.isTargetPending)

            fixture.lookup.finishAll()
            #expect(model.target == editor)

            fixture.controller.commit()
            await yieldUntil { fixture.inserter.calls.count == 1 }

            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "hello")
            #expect(fixture.inserter.calls.first?.target == editor)
        }
    }

    // MARK: - AC-15

    @Test("AC-15: 先に出したパネルは、開いた時点で入力欄へのフォーカスが求められ、前に出る")
    func slowOpenRequestsFocusAndShowsPanel() async throws {
        try await withFixture(isAnimationEnabled: true) { fixture in
            fixture.lookup.respondsLate = true
            fixture.use(editor)
            let focusRequestsBefore = fixture.controller.model.focusRequest

            fixture.controller.open()

            #expect(fixture.controller.model.focusRequest > focusRequestsBefore)
            #expect(fixture.animator.calls.count == 1)
            #expect(fixture.animator.calls.first?.isVisible == true)
            #expect(fixture.controller.panel.isVisible)
            #expect(fixture.controller.panel.canBecomeKey)
        }
    }
}
