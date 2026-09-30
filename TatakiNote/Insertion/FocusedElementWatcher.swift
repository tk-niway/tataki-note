import AppKit
import ApplicationServices
import Observation

/// @note p0-39
final class FocusedElementWatcher {
    /// @note p0-40
    static let activationGrace: TimeInterval = 0.25
    /// @note p0-41
    static let dismissGrace: TimeInterval = 0.5

    /// @note p0-42
    private struct ShownElement {
        let processIdentifier: pid_t
        let element: AXUIElement?
    }

    private let settings: AppSettings
    private let panelModel: PanelModel
    private let permission: AccessibilityPermissionChecking
    private let probe: FocusedElementProbing
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let ownProcessIdentifier: pid_t
    private let primaryScreenFrame: () -> CGRect
    private let mouseLocation: () -> CGPoint
    private let now: () -> Date
    private let exposeWebContent: (InsertionTarget) -> Void
    private let onShow: () -> Void

    private var activationObserver: (any NSObjectProtocol)?
    private var clickMonitor: Any?
    private var focusObservation: FocusObservation?

    /// @note p0-43
    private var target: InsertionTarget?
    private var lastActivatedAt: Date?
    /// @note p0-44
    private(set) var panelDismissedAt: Date?
    private var lastShown: ShownElement?

    /// @note p0-45
    init(
        settings: AppSettings,
        panelModel: PanelModel,
        permission: AccessibilityPermissionChecking,
        probe: FocusedElementProbing = AXFocusedTextInputInspector(),
        workspace: NSWorkspace = .shared,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        primaryScreenFrame: @escaping () -> CGRect = { NSScreen.screens.first?.frame ?? .zero },
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
        // @note p0-46
        self.notificationCenter = workspace.notificationCenter
        self.ownProcessIdentifier = ownProcessIdentifier
        self.primaryScreenFrame = primaryScreenFrame
        self.mouseLocation = mouseLocation
        self.now = now
        self.exposeWebContent = exposeWebContent
        self.onShow = onShow

        // @note p0-47
        observePanelDismissal()
    }

    deinit {
        // @note p0-48
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        focusObservation?.remove()
    }

    func start() {
        guard activationObserver == nil else { return }
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handleActivation(of: app.map { InsertionTarget($0) })
            }
        }
        // @note p0-49
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            // @note p0-50
            MainActor.assumeIsolated {
                self?.handleClick()
            }
        }
        // @note p0-51
        handleActivation(of: workspace.frontmostApplication.map { InsertionTarget($0) })
    }

    func stop() {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        stopWatchingFocus()
    }

    /// @note p0-52
    func handleActivation(of target: InsertionTarget?) {
        lastActivatedAt = now()
        stopWatchingFocus()
        // @note p0-53
        self.target = target
        guard let target, shouldWatch(target) else { return }
        watchFocus(of: target)
        // @note p0-54
        exposeWebContent(target)
    }

    func handleFocusChanged() {
        evaluate(trigger: .focusChanged)
    }

    func handleClick() {
        evaluate(trigger: .userClick)
    }

    /// @note p0-55
    func handlePanelDismissed() {
        panelDismissedAt = now()
    }

    // MARK: - 判定

    private func shouldWatch(_ target: InsertionTarget) -> Bool {
        AutoShowDecision.shouldWatch(
            mode: settings.autoShowMode,
            selectedApps: settings.autoShowApps,
            isAccessibilityTrusted: permission.isTrusted,
            isOwnApp: target.processIdentifier == ownProcessIdentifier,
            bundleIdentifier: target.bundleIdentifier
        )
    }

    private func evaluate(trigger: AutoShowTrigger) {
        // @note p0-56
        guard !panelModel.isPresented, let target, shouldWatch(target) else { return }

        let focused = probe.probeFocusedElement(in: target, readsFrame: trigger == .userClick)

        // @note p0-57
        if trigger == .focusChanged, let lastShown, lastShown.processIdentifier == target.processIdentifier,
           !Self.isSameElement(lastShown.element, focused.element) {
            self.lastShown = nil
        }
        let isSameElementAsLastShown = lastShown.map {
            $0.processIdentifier == target.processIdentifier && Self.isSameElement($0.element, focused.element)
        } ?? false

        // @note p0-58
        var isClickInsideFocusedElement = false
        if trigger == .userClick, let frame = focused.frame {
            let point = AutoShowDecision.accessibilityPoint(fromCocoa: mouseLocation(), primaryScreenFrame: primaryScreenFrame())
            isClickInsideFocusedElement = frame.contains(point)
        }

        let currentTime = now()
        let input = AutoShowInput(
            mode: settings.autoShowMode,
            selectedApps: settings.autoShowApps,
            isAccessibilityTrusted: permission.isTrusted,
            isPanelPresented: panelModel.isPresented,
            isFrontmostOwnApp: target.processIdentifier == ownProcessIdentifier,
            frontmostBundleIdentifier: target.bundleIdentifier,
            focusState: FocusedTextInputState.classify(focused.lookup),
            focusedSubrole: focused.subrole,
            trigger: trigger,
            isSameElementAsLastShown: isSameElementAsLastShown,
            isJustActivated: Self.isWithin(Self.activationGrace, since: lastActivatedAt, now: currentTime),
            isJustDismissed: Self.isWithin(Self.dismissGrace, since: panelDismissedAt, now: currentTime),
            isClickInsideFocusedElement: isClickInsideFocusedElement
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

    /// @note p0-59
    private func observePanelDismissal() {
        withObservationTracking {
            _ = panelModel.isPresented
        } onChange: { [weak self] in
            // @note p0-60
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.panelModel.isPresented {
                    self.handlePanelDismissed()
                }
                self.observePanelDismissal()
            }
        }
    }

    // MARK: - AX の監視

    private func watchFocus(of target: InsertionTarget) {
        let pid = target.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        // @note p0-61
        AXUIElementSetMessagingTimeout(application, AXFocusedTextInputInspector.messagingTimeout)

        // @note p0-62
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

/// @note p0-63
private nonisolated struct FocusObservation {
    let observer: AXObserver
    let application: AXUIElement

    /// @note p0-64
    func remove() {
        AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// @note p0-65
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
