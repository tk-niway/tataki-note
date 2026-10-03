import AppKit
import ApplicationServices
import Observation

/// 他のアプリで入力欄が選ばれたことを見張り、条件が合えばパネルを出す。
final class FocusedElementWatcher {
    static let activationGrace: TimeInterval = 0.25
    static let dismissGrace: TimeInterval = 0.5
    static let clickSuppressionDuration: TimeInterval = 30

    private struct ShownElement {
        let processIdentifier: pid_t
        let element: AXUIElement?
    }

    private struct ClickSuppression {
        let processIdentifier: pid_t
        let element: AXUIElement
        let since: Date
    }

    private let settings: AppSettings
    private let panelModel: PanelModel
    private let permission: AccessibilityPermissionChecking
    private let probe: FocusedElementProbing
    private let workspace: NSWorkspace
    private let ownProcessIdentifier: pid_t
    private let primaryScreenFrame: () -> CGRect
    private let mouseLocation: () -> CGPoint
    private let now: () -> Date
    private let exposeWebContent: (InsertionTarget) -> Void
    private let onShow: () -> Void

    private var activationObserver: FrontmostAppObserver?
    private var clickMonitor: Any?
    private var focusObservation: FocusObservation?

    private var target: InsertionTarget?
    private var lastActivatedAt: Date?
    private(set) var panelDismissedAt: Date?
    private var lastShown: ShownElement?
    private var clickSuppression: ClickSuppression?

    /// 挿入せずに閉じたあとの入力欄のクリックを、いま抑えているか。
    var isSuppressingClicks: Bool { clickSuppression != nil }

    init(
        settings: AppSettings,
        panelModel: PanelModel,
        permission: AccessibilityPermissionChecking,
        probe: FocusedElementProbing = AXFocusedTextInputInspector(),
        workspace: NSWorkspace = .shared,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        primaryScreenFrame: @escaping () -> CGRect = { ScreenCoordinates.primaryScreenFrame ?? .zero },
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        now: @escaping () -> Date = Date.init,
        exposeWebContent: @escaping (InsertionTarget) -> Void = { AXFocusedTextInputInspector.exposeWebContent(of: $0) },
        onShow: @escaping () -> Void
    ) {
        self.settings = settings
        self.panelModel = panelModel
        self.permission = permission
        self.probe = probe
        self.workspace = workspace
        self.ownProcessIdentifier = ownProcessIdentifier
        self.primaryScreenFrame = primaryScreenFrame
        self.mouseLocation = mouseLocation
        self.now = now
        self.exposeWebContent = exposeWebContent
        self.onShow = onShow

        observePanelDismissal()
    }

    deinit {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        focusObservation?.remove()
    }

    func start() {
        guard activationObserver == nil else { return }
        activationObserver = FrontmostAppObserver(notificationCenter: workspace.notificationCenter) { [weak self] app in
            self?.handleActivation(of: app.map { InsertionTarget($0) })
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleClick()
            }
        }
        handleActivation(of: workspace.frontmostApplication.map { InsertionTarget($0) })
    }

    func stop() {
        activationObserver = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        stopWatchingFocus()
        clickSuppression = nil
    }

    func handleActivation(of target: InsertionTarget?) {
        lastActivatedAt = now()
        if let clickSuppression, clickSuppression.processIdentifier != target?.processIdentifier {
            self.clickSuppression = nil
        }
        stopWatchingFocus()
        self.target = target
        guard let target, shouldWatch(target) else { return }
        watchFocus(of: target)
        exposeWebContent(target)
    }

    func handleFocusChanged() {
        evaluate(trigger: .focusChanged)
    }

    func handleClick() {
        evaluate(trigger: .userClick)
    }

    func handlePanelDismissed(_ dismissal: PanelDismissal, panelTarget: InsertionTarget?) {
        let dismissedAt = now()
        panelDismissedAt = dismissedAt
        clickSuppression = nil

        guard dismissal == .cancelled,
              let target, shouldWatch(target),
              panelTarget?.processIdentifier == target.processIdentifier else { return }
        guard let element = probe.probeFocusedElement(in: target, readsFrame: false).element else { return }
        clickSuppression = ClickSuppression(processIdentifier: target.processIdentifier, element: element, since: dismissedAt)
    }

    // MARK: - 判定

    private func shouldWatch(_ target: InsertionTarget) -> Bool {
        AutoShowDecision.shouldWatch(
            mode: settings.autoShowMode,
            selectedApps: settings.autoShowApps,
            isAccessibilityTrusted: permission.isTrusted,
            isOwnApp: target.isOwnApp(ownProcessIdentifier),
            bundleIdentifier: target.bundleIdentifier
        )
    }

    private func evaluate(trigger: AutoShowTrigger) {
        guard !panelModel.isPresented, let target, shouldWatch(target) else { return }

        let focused = probe.probeFocusedElement(in: target, readsFrame: trigger == .userClick)

        if trigger == .focusChanged, let lastShown, lastShown.processIdentifier == target.processIdentifier,
           !Self.isSameElement(lastShown.element, focused.element) {
            self.lastShown = nil
        }
        let currentTime = now()
        if trigger == .focusChanged, let clickSuppression, clickSuppression.processIdentifier == target.processIdentifier,
           !Self.isSameElement(clickSuppression.element, focused.element) {
            self.clickSuppression = nil
        }
        if trigger == .userClick, let clickSuppression,
           currentTime.timeIntervalSince(clickSuppression.since) >= Self.clickSuppressionDuration {
            self.clickSuppression = nil
        }
        let isClickSuppressed = trigger == .userClick && (clickSuppression.map {
            $0.processIdentifier == target.processIdentifier && Self.isSameElement($0.element, focused.element)
        } ?? false)
        let isSameElementAsLastShown = lastShown.map {
            $0.processIdentifier == target.processIdentifier && Self.isSameElement($0.element, focused.element)
        } ?? false

        var isClickInsideFocusedElement = false
        if trigger == .userClick, let frame = focused.frame {
            let point = AutoShowDecision.accessibilityPoint(fromCocoa: mouseLocation(), primaryScreenFrame: primaryScreenFrame())
            isClickInsideFocusedElement = frame.contains(point)
        }

        let input = AutoShowInput(
            mode: settings.autoShowMode,
            selectedApps: settings.autoShowApps,
            isAccessibilityTrusted: permission.isTrusted,
            isPanelPresented: panelModel.isPresented,
            isFrontmostOwnApp: target.isOwnApp(ownProcessIdentifier),
            frontmostBundleIdentifier: target.bundleIdentifier,
            focusState: FocusedTextInputState.classify(focused.lookup),
            focusedSubrole: focused.subrole,
            trigger: trigger,
            isSameElementAsLastShown: isSameElementAsLastShown,
            isJustActivated: Self.isWithin(Self.activationGrace, since: lastActivatedAt, now: currentTime),
            isJustDismissed: Self.isWithin(Self.dismissGrace, since: panelDismissedAt, now: currentTime),
            isClickInsideFocusedElement: isClickInsideFocusedElement,
            isClickSuppressed: isClickSuppressed
        )
        guard AutoShowDecision.shouldShow(input) else { return }
        lastShown = ShownElement(processIdentifier: target.processIdentifier, element: focused.element)
        onShow()
    }

    private static func isSameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        guard let lhs, let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private static func isWithin(_ grace: TimeInterval, since date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < grace
    }

    // MARK: - パネルが閉じた時刻

    private func observePanelDismissal() {
        observeRepeatedly(
            tracking: { [weak self] in
                _ = self?.panelModel.isPresented
            },
            onChange: { [weak self] in
                guard let self else { return false }
                if !self.panelModel.isPresented {
                    self.handlePanelDismissed(self.panelModel.lastDismissal ?? .committed, panelTarget: self.panelModel.target)
                }
                return true
            }
        )
    }

    // MARK: - AX の監視

    private func watchFocus(of target: InsertionTarget) {
        let pid = target.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXFocusedTextInputInspector.messagingTimeout)

        var created: AXObserver?
        guard AXObserverCreate(pid, focusedElementChanged, &created) == .success, let observer = created else {
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(
            observer,
            application,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        ) == .success else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        focusObservation = FocusObservation(observer: observer, application: application)
    }

    private func stopWatchingFocus() {
        focusObservation?.remove()
        focusObservation = nil
    }
}

private nonisolated struct FocusObservation {
    let observer: AXObserver
    let application: AXUIElement

    func remove() {
        AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

private nonisolated func focusedElementChanged(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    MainActor.assumeIsolated {
        Unmanaged<FocusedElementWatcher>.fromOpaque(refcon).takeUnretainedValue().handleFocusChanged()
    }
}
