import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class OpenEventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

@MainActor
struct PanelControllerTargetMonitorTests {
    private static let ownPid: pid_t = 4242

    private let editor = WatcherFixture.editor
    private let own = InsertionTarget(processIdentifier: PanelControllerTargetMonitorTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let element = AXUIElementCreateApplication(pid_t.max)
    private let fieldRect = CGRect(x: 100, y: 100, width: 200, height: 40)
    private let elementRect = CGRect(x: 120, y: 120, width: 180, height: 30)

    nonisolated enum Observed: CaseIterable, Sendable {
        case none
        case sameAppWithFrame
        case sameAppWithoutFrame
        case sameAppNotTextInput
        case anotherApp

        var expectedProbes: Int {
            switch self {
            case .none, .anotherApp: 1
            case .sameAppWithFrame, .sameAppWithoutFrame, .sameAppNotTextInput: 0
            }
        }

        var expectedFrameRequests: Int {
            self == .sameAppWithoutFrame ? 1 : 0
        }

        var hasTextInput: Bool {
            self != .sameAppNotTextInput
        }
    }

    private func textInputProbe(frame: CGRect?) -> FocusedElementProbe {
        FocusedElementProbe(element: element, lookup: WatcherFixture.textFieldLookup, frame: frame)
    }

    private func observedFocus(_ observed: Observed, for target: InsertionTarget) -> ObservedFocus? {
        switch observed {
        case .none:
            return nil
        case .sameAppWithFrame:
            return ObservedFocus(processIdentifier: target.processIdentifier, probe: textInputProbe(frame: fieldRect))
        case .sameAppWithoutFrame:
            return ObservedFocus(processIdentifier: target.processIdentifier, probe: textInputProbe(frame: nil))
        case .sameAppNotTextInput:
            return ObservedFocus(
                processIdentifier: target.processIdentifier,
                probe: FocusedElementProbe(element: element, lookup: WatcherFixture.buttonLookup, frame: nil)
            )
        case .anotherApp:
            return ObservedFocus(processIdentifier: WatcherFixture.otherApp.processIdentifier, probe: textInputProbe(frame: fieldRect))
        }
    }

    private func withController(
        mode: PanelScreen,
        target: InsertionTarget,
        isTrusted: Bool = true,
        isTargetLookupDisabled: Bool = false,
        log: OpenEventLog? = nil,
        _ body: (PanelController, PerAppProbeStub) throws -> Void
    ) throws {
        let log = log ?? OpenEventLog()
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = mode
        let probe = PerAppProbeStub()
        probe.results[target.processIdentifier] = textInputProbe(frame: fieldRect)
        probe.elementFrame = elementRect
        probe.onProbe = { log.record("probe") }
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: isTrusted),
            fieldProbe: probe,
            exposeWebContent: { _ in log.record("expose") },
            ownProcessIdentifier: Self.ownPid,
            beep: {},
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        controller.targetOverride = { target }
        controller.isTargetLookupDisabled = isTargetLookupDisabled
        defer { controller.close() }
        try body(controller, probe)
    }

    @Test("AC-25: 他のアプリが挿入先のとき、自動表示の結果があれば問い合わせず(枠が無ければ要素の枠を1回だけ読み)、無ければ出し方によらず1回問い合わせる", arguments: [PanelScreen.nearFocusedField, PanelScreen.mouse], Observed.allCases)
    func openQueriesAtMostOnceForOtherApp(mode: PanelScreen, observed: Observed) throws {
        try withController(mode: mode, target: editor) { controller, probe in
            controller.open(observedFocus: observedFocus(observed, for: editor))

            #expect(probe.targets.count == observed.expectedProbes)
            #expect(probe.targets.allSatisfy { $0 == editor })
            #expect(probe.frameRequests.count == observed.expectedFrameRequests)
            #expect(controller.model.target == (observed.hasTextInput ? editor : nil))
        }
    }

    @Test("AC-25: TatakiNote 自身が挿入先のときは、出し方・自動表示の結果によらず問い合わせず、挿入先は自分自身になる", arguments: [PanelScreen.nearFocusedField, PanelScreen.mouse], [Observed.none, Observed.sameAppWithFrame, Observed.sameAppWithoutFrame])
    func openDoesNotQueryForOwnApp(mode: PanelScreen, observed: Observed) throws {
        try withController(mode: mode, target: own) { controller, probe in
            controller.open(observedFocus: observedFocus(observed, for: own))

            #expect(probe.targets.isEmpty)
            #expect(probe.frameRequests.isEmpty)
            #expect(controller.model.target == own)
        }
    }

    @Test("AC-25: 挿入先を探さない設定のときは、出し方によらず問い合わせず、挿入先は無い", arguments: [PanelScreen.nearFocusedField, PanelScreen.mouse], [Observed.none, Observed.sameAppWithFrame, Observed.anotherApp])
    func openDoesNotQueryWhenLookupDisabled(mode: PanelScreen, observed: Observed) throws {
        try withController(mode: mode, target: editor, isTargetLookupDisabled: true) { controller, probe in
            controller.open(observedFocus: observedFocus(observed, for: editor))

            #expect(probe.targets.isEmpty)
            #expect(probe.frameRequests.isEmpty)
            #expect(controller.model.target == nil)
        }
    }

    @Test("AC-25: Web の中身を出す頼みは、フォーカスのある要素への問い合わせより先に行われる", arguments: [PanelScreen.nearFocusedField, PanelScreen.mouse])
    func exposeWebContentComesBeforeProbe(mode: PanelScreen) throws {
        let log = OpenEventLog()
        try withController(mode: mode, target: editor, log: log) { controller, probe in
            controller.open()

            #expect(log.events == ["expose", "probe"])
            #expect(probe.targets == [editor])
        }
    }

    @Test("AC-25: 開いているパネルをもう一度開こうとしても、問い合わせも Web の中身を出す頼みも増えない")
    func reopeningPresentedPanelDoesNotQueryAgain() throws {
        let log = OpenEventLog()
        try withController(mode: .nearFocusedField, target: editor, log: log) { controller, probe in
            controller.open()
            controller.open()

            #expect(log.events == ["expose", "probe"])
            #expect(probe.targets == [editor])
        }
    }
}
