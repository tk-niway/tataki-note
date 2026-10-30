import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class MonitorEnvironment {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    var stoppedProcesses: Set<pid_t> = []
    var frontmost: InsertionTarget?
    var windows: [OnScreenWindow] = []
    var windowListCalls = 0
    var mouse = CGPoint.zero
    var exposed: [InsertionTarget] = []
    var isOutlineEnabled = true
    var isOwnTargetAvailable = true
    var adoptedCount = 0
}

@MainActor
final class MonitorFixture {
    static let ownPid: pid_t = 4242
    static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let editor = InsertionTarget(processIdentifier: 5001, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
    static let browser = InsertionTarget(processIdentifier: 5002, bundleIdentifier: "com.example.Browser", localizedName: "Browser")
    static let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    static let fieldA = AXUIElementCreateApplication(7001)
    static let fieldB = AXUIElementCreateApplication(7002)
    static let frameA = CGRect(x: 100, y: 100, width: 300, height: 40)
    static let frameB = CGRect(x: 100, y: 200, width: 300, height: 40)
    static let textField = FocusedElementLookup.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: true)
    static let secureTextField = FocusedElementLookup.element(
        role: "AXTextField", subrole: "AXSecureTextField", isSelectedTextRangeSettable: true
    )
    static let button = FocusedElementLookup.element(role: "AXButton", subrole: nil, isSelectedTextRangeSettable: false)
    static let unknownGroup = FocusedElementLookup.element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: false)

    let env = MonitorEnvironment()
    let model = PanelModel()
    let probe = PerAppProbeStub()
    let clicks = ClickMonitorStub()
    let monitor: InsertionTargetMonitor

    init(polls: Bool = false) {
        let env = env
        let probe = probe
        let clicks = clicks
        env.windows = [Self.window(of: Self.editor)]
        let sleep: (Duration) async -> Void = polls ? { _ in await Task.yield() } : { _ in }
        let monitor = InsertionTargetMonitor(
            panelModel: model,
            probe: probe,
            ownProcessIdentifier: Self.ownPid,
            exposeWebContent: { env.exposed.append($0) },
            isOutlineEnabled: { env.isOutlineEnabled },
            frontmostApplication: { env.frontmost },
            isRunning: { !env.stoppedProcesses.contains($0) },
            onScreenWindows: {
                env.windowListCalls += 1
                return env.windows
            },
            mouseLocation: { env.mouse },
            primaryScreenFrame: { MonitorFixture.screen },
            now: { env.now },
            sleep: sleep,
            pollsAutomatically: polls,
            addClickMonitor: { clicks.add($0) },
            removeClickMonitor: { clicks.remove($0) }
        )
        monitor.isOwnTargetAvailable = { env.isOwnTargetAvailable }
        monitor.onFieldAdopted = { env.adoptedCount += 1 }
        self.monitor = monitor
    }

    static func window(of target: InsertionTarget) -> OnScreenWindow {
        OnScreenWindow(processIdentifier: target.processIdentifier, layer: 0, bounds: screen)
    }

    func focus(
        _ element: AXUIElement?,
        frame: CGRect?,
        lookup: FocusedElementLookup = MonitorFixture.textField,
        in target: InsertionTarget
    ) {
        probe.results[target.processIdentifier] = FocusedElementProbe(element: element, lookup: lookup, frame: frame)
        if let element {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            probe.elementFrames[pid] = frame
        }
    }

    @discardableResult
    func open(_ app: InsertionTarget?, observedFocus: ObservedFocus? = nil) -> InsertionTargetStart {
        let start = monitor.begin(app: app, observedFocus: observedFocus)
        model.present(target: start.target)
        return start
    }

    func clickPoint(inside frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: Self.screen.maxY - frame.midY)
    }

    func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
final class MonitorBox {
    var monitor: InsertionTargetMonitor?
}

@MainActor
final class WindowFrameLocateRecorder {
    var frame: CGRect?
    private(set) var processIdentifiers: [pid_t] = []

    var count: Int { processIdentifiers.count }

    func locate(_ processIdentifier: pid_t) -> CGRect? {
        processIdentifiers.append(processIdentifier)
        return frame
    }
}
