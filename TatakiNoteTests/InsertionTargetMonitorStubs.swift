import ApplicationServices
import Foundation
@testable import TatakiNote

@MainActor
final class PerAppProbeStub: FocusedElementProbing {
    var results: [pid_t: FocusedElementProbe] = [:]
    var elementFrame: CGRect?
    var elementFrames: [pid_t: CGRect] = [:]
    var onProbe: (() -> Void)?
    var onFrameRequest: (() -> Void)?
    private(set) var targets: [InsertionTarget] = []
    private(set) var readsFrameValues: [Bool] = []
    private(set) var frameRequests: [AXUIElement] = []

    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
        targets.append(target)
        readsFrameValues.append(readsFrame)
        onProbe?()
        return results[target.processIdentifier] ?? FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
    }

    func frame(of element: AXUIElement) -> CGRect? {
        frameRequests.append(element)
        onFrameRequest?()
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return elementFrames[pid] ?? elementFrame
    }

    func probeCount(for target: InsertionTarget) -> Int {
        targets.filter { $0 == target }.count
    }
}

@MainActor
final class ClickMonitorStub {
    private(set) var added = 0
    private(set) var removed = 0
    private var handlers: [Int: () -> Void] = [:]

    var activeCount: Int { handlers.count }

    func add(_ handler: @escaping () -> Void) -> Any? {
        added += 1
        handlers[added] = handler
        return added
    }

    func remove(_ token: Any) {
        removed += 1
        if let token = token as? Int {
            handlers[token] = nil
        }
    }

    func fire() {
        for handler in handlers.values {
            handler()
        }
    }
}

extension InsertionTargetMonitor {
    static func testFactory(
        probe: FocusedElementProbing,
        ownProcessIdentifier: pid_t,
        isRunning: @escaping (pid_t) -> Bool = { _ in true },
        frontmostApplication: @escaping () -> InsertionTarget? = { nil }
    ) -> (PanelModel) -> InsertionTargetMonitor {
        { model in
            InsertionTargetMonitor(
                panelModel: model,
                probe: probe,
                ownProcessIdentifier: ownProcessIdentifier,
                exposeWebContent: { _ in },
                isOutlineEnabled: { true },
                frontmostApplication: frontmostApplication,
                isRunning: isRunning,
                onScreenWindows: { [] },
                mouseLocation: { .zero },
                sleep: { _ in },
                pollsAutomatically: false,
                addClickMonitor: { _ in nil },
                removeClickMonitor: { _ in }
            )
        }
    }
}
