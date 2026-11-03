import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private struct AlreadyAnsweredOpeningTargetLookup: OpeningTargetLookup {
    let result: OpeningTargetLookupResult

    func lookUp(_ request: OpeningTargetLookupRequest, waitingUpTo deadline: Duration) -> OpeningTargetLookupOutcome {
        let lookup = PendingOpeningTargetLookup()
        lookup.finish(result)
        return .pending(lookup)
    }
}

@MainActor
private final class StateRecordingPointerEventMonitor: PanelPointerEventMonitoring {
    struct Snapshot {
        let isTargetPending: Bool
        let target: InsertionTarget?
    }

    private let model: PanelModel
    private(set) var snapshots: [Snapshot] = []

    init(model: PanelModel) {
        self.model = model
    }

    func start(_ handler: @escaping (PanelPointerEvent) -> Void) {
        snapshots.append(Snapshot(isTargetPending: model.isTargetPending, target: model.target))
    }

    func stop() {}
}

@MainActor
struct PanelControllerOpeningTargetTests {
    @Test("AC-8: 答えが先に届いていても、ポインタの操作を始める時点では待ちのままで、open() の後に挿入先が決まり、開く動きは1回で、入力欄へ問い合わせない")
    func answerArrivedBeforeOpenIsDeliveredAfterPointerStart() throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.animationMode = .on
        let model = PanelModel()
        let probe = PerAppProbeStub()
        let animator = FakePanelFrameAnimator()
        let pointerMonitor = StateRecordingPointerEventMonitor(model: model)
        let result = OpeningTargetLookupResult(
            probe: FocusedElementProbe(
                element: MonitorFixture.fieldA,
                lookup: MonitorFixture.textField,
                frame: MonitorFixture.frameA
            ),
            didQuery: true,
            duration: 0
        )
        let controller = PanelControllerFactory.make(
            settings: settings,
            model: model,
            probe: probe,
            openingLookup: AlreadyAnsweredOpeningTargetLookup(result: result),
            ownProcessIdentifier: MonitorFixture.ownPid,
            animator: animator,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(
                probe: probe,
                ownProcessIdentifier: MonitorFixture.ownPid
            ),
            pointerEventMonitor: pointerMonitor
        )
        defer { controller.panel.orderOut(nil) }
        controller.targetOverride = { MonitorFixture.editor }

        controller.open()

        let snapshot = try #require(pointerMonitor.snapshots.first)
        #expect(pointerMonitor.snapshots.count == 1)
        #expect(snapshot.isTargetPending)
        #expect(snapshot.target == nil)
        #expect(model.target == MonitorFixture.editor)
        #expect(!model.isTargetPending)
        #expect(model.pendingLookupApp == nil)
        #expect(animator.calls.count == 1)
        #expect(probe.targets.isEmpty)
    }
}
