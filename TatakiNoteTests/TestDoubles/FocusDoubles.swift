import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class FocusedElementProbeStub: FocusedElementProbing {
    var result: FocusedElementProbe
    private(set) var targets: [InsertionTarget] = []
    private(set) var readsFrameValues: [Bool] = []
    private(set) var frameRequests: [AXUIElement] = []
    var elementFrame: CGRect?

    init() {
        result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
    }

    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
        targets.append(target)
        readsFrameValues.append(readsFrame)
        return result
    }

    func frame(of element: AXUIElement) -> CGRect? {
        frameRequests.append(element)
        return elementFrame
    }
}

@MainActor
final class WatcherEnvironment {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    var mouseLocation = CGPoint.zero
    var showCount = 0
    var exposedTargets: [InsertionTarget] = []
    var shownFocuses: [ObservedFocus] = []
    private(set) var clickMonitorsAdded = 0
    private(set) var clickMonitorsRemoved = 0
    private var activeClickMonitors: [Int: () -> Void] = [:]

    var activeClickMonitorCount: Int { activeClickMonitors.count }

    func addClickMonitor(_ handler: @escaping () -> Void) -> Any? {
        clickMonitorsAdded += 1
        let token = clickMonitorsAdded
        activeClickMonitors[token] = handler
        return token
    }

    func removeClickMonitor(_ token: Any) {
        clickMonitorsRemoved += 1
        if let token = token as? Int {
            activeClickMonitors[token] = nil
        }
    }

    func fireClick() {
        for handler in activeClickMonitors.values {
            handler()
        }
    }
}

@MainActor
final class WatcherFixture {
    static let primaryScreenFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let editor = InsertionTarget(processIdentifier: pid_t.max, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
    static let otherApp = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    static let editorApp = AutoShowApp(bundleIdentifier: "com.example.Editor", name: "Editor")
    static let otherAutoShowApp = AutoShowApp(bundleIdentifier: "com.example.Other", name: "Other")

    static let textFieldLookup = FocusedElementLookup.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: true)
    static let buttonLookup = FocusedElementLookup.element(role: "AXButton", subrole: nil, isSelectedTextRangeSettable: false)

    let settings: AppSettings
    let panelModel: PanelModel
    let probe: FocusedElementProbeStub
    let environment: WatcherEnvironment
    let watcher: FocusedElementWatcher
    private let defaults: InMemoryDefaults
    private let suiteName: String

    init(isTrusted: Bool = true, exposeWebContent: ((InsertionTarget) -> Void)? = nil) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .allApps
        let panelModel = PanelModel()
        let probe = FocusedElementProbeStub()
        let environment = WatcherEnvironment()
        let screenFrame = Self.primaryScreenFrame

        self.suiteName = suiteName
        self.defaults = defaults
        self.settings = settings
        self.panelModel = panelModel
        self.probe = probe
        self.environment = environment
        self.watcher = FocusedElementWatcher(
            settings: settings,
            panelModel: panelModel,
            permission: OverriddenAccessibilityPermission(isTrusted: isTrusted),
            probe: probe,
            primaryScreenFrame: { screenFrame },
            mouseLocation: { environment.mouseLocation },
            now: { environment.now },
            exposeWebContent: {
                environment.exposedTargets.append($0)
                exposeWebContent?($0)
            },
            addClickMonitor: { environment.addClickMonitor($0) },
            removeClickMonitor: { environment.removeClickMonitor($0) },
            onShow: {
                environment.showCount += 1
                environment.shownFocuses.append($0)
            }
        )
    }

    func removeSuite() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    var showCount: Int { environment.showCount }

    func advance(by interval: TimeInterval) {
        environment.now += interval
    }

    func activate(_ target: InsertionTarget?) {
        watcher.handleActivation(of: target)
        advance(by: FocusedElementWatcher.activationGrace + 0.01)
    }

    func dismissAndWait(_ dismissal: PanelDismissal = .cancelled) {
        watcher.handlePanelDismissed(dismissal, panelTarget: Self.editor)
        advance(by: FocusedElementWatcher.dismissGrace + 0.01)
    }

    func focusTextField(_ element: AXUIElement, frame: CGRect? = nil) {
        probe.result = FocusedElementProbe(element: element, lookup: Self.textFieldLookup, frame: frame)
    }

    func focusButton(_ element: AXUIElement) {
        probe.result = FocusedElementProbe(element: element, lookup: Self.buttonLookup, frame: nil)
    }
}
