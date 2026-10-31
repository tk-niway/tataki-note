import AppKit
import ApplicationServices
import Observation

/// 開くときの調べの番号。
struct InsertionTargetLookupToken: Equatable {
    let value: UInt64
}

/// 見張りを始めた時点の挿入先と、そのとき使ったフォーカスのある要素の調べの結果。
struct InsertionTargetStart {
    let target: InsertionTarget?
    /// 使った調べの結果。調べなかったときは nil。
    let focus: ObservedFocus?
}

/// パネルを開いている間、挿入先(今確定したら文章が入る入力欄)を見張る。
final class InsertionTargetMonitor {
    static let pollInterval: Duration = .milliseconds(100)
    static let slowQueryThreshold: TimeInterval = 0.03
    static let slowQueryBackoff: TimeInterval = 0.5
    static let clickRecheckDelay: Duration = .milliseconds(200)

    private struct Resolution {
        var target: InsertionTarget?
        var outline: CGRect?
        var focus: ObservedFocus?
    }

    /// 枠線の場所。
    let outline = InsertionTargetOutlineModel()
    /// TatakiNote 自身が挿入先のとき、その入力欄がまだ使えるか。nil なら使えるとみなす。
    var isOwnTargetAvailable: (() -> Bool)?
    /// クリックで他のアプリの入力欄を挿入先に選んだときに呼ばれる。
    var onFieldAdopted: (() -> Void)?

    private let panelModel: PanelModel
    private let probe: FocusedElementProbing
    private let ownProcessIdentifier: pid_t
    private let exposeWebContent: (InsertionTarget) -> Void
    private let isOutlineEnabled: () -> Bool
    private let frontmostApplication: () -> InsertionTarget?
    private let isRunning: (pid_t) -> Bool
    private let onScreenWindows: () -> [OnScreenWindow]
    private let mouseLocation: () -> CGPoint
    private let primaryScreenFrame: () -> CGRect
    private let now: () -> Date
    private let sleep: (Duration) async -> Void
    private let pollsAutomatically: Bool
    private let addClickMonitor: (@escaping () -> Void) -> Any?
    private let removeClickMonitor: (Any) -> Void

    private var app: InsertionTarget?
    private var field: AXUIElement?
    private var hasReadableFrame = false
    private var isWatching = false
    private var slowUntil: Date?
    private var pendingToken: InsertionTargetLookupToken?
    private var nextTokenValue: UInt64 = 0
    private var pollTask: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?
    private var clickMonitor: Any?

    init(
        panelModel: PanelModel,
        probe: FocusedElementProbing,
        ownProcessIdentifier: pid_t,
        exposeWebContent: @escaping (InsertionTarget) -> Void,
        isOutlineEnabled: @escaping () -> Bool,
        frontmostApplication: @escaping () -> InsertionTarget? = {
            NSWorkspace.shared.frontmostApplication.map { InsertionTarget($0) }
        },
        isRunning: @escaping (pid_t) -> Bool = { RunningApplicationActivationRequester().isRunning($0) },
        onScreenWindows: @escaping () -> [OnScreenWindow] = { TargetWindowLocator.onScreenWindows() },
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        primaryScreenFrame: @escaping () -> CGRect = { ScreenCoordinates.primaryScreenFrame ?? .zero },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        pollsAutomatically: Bool = true,
        addClickMonitor: @escaping (@escaping () -> Void) -> Any? = { handler in
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
                MainActor.assumeIsolated {
                    handler()
                }
            }
        },
        removeClickMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.panelModel = panelModel
        self.probe = probe
        self.ownProcessIdentifier = ownProcessIdentifier
        self.exposeWebContent = exposeWebContent
        self.isOutlineEnabled = isOutlineEnabled
        self.frontmostApplication = frontmostApplication
        self.isRunning = isRunning
        self.onScreenWindows = onScreenWindows
        self.mouseLocation = mouseLocation
        self.primaryScreenFrame = primaryScreenFrame
        self.now = now
        self.sleep = sleep
        self.pollsAutomatically = pollsAutomatically
        self.addClickMonitor = addClickMonitor
        self.removeClickMonitor = removeClickMonitor

        observePanelDismissal()
    }

    deinit {
        pollTask?.cancel()
        recheckTask?.cancel()
        if let clickMonitor {
            removeClickMonitor(clickMonitor)
        }
    }

    // MARK: - 開始と終了

    /// 見張りを始め、始めた時点の挿入先(入力欄があるときだけアプリ、無ければ nil)と使った調べの結果を返す。
    @discardableResult
    func begin(app: InsertionTarget?, observedFocus: ObservedFocus? = nil) -> InsertionTargetStart {
        end()
        self.app = app
        isWatching = true
        let resolution = measured { resolveAtOpen(observedFocus: observedFocus, didQuery: &$0) }
        outline.update(resolution.outline)
        startClickMonitor()
        startPolling()
        return InsertionTargetStart(target: resolution.target, focus: resolution.focus)
    }

    /// 開くときに、裏で調べる必要がある挿入先か(他のアプリで、動いている)。
    func needsOpeningLookup(for app: InsertionTarget?) -> Bool {
        guard let app else { return false }
        return !app.isOwnApp(ownProcessIdentifier) && isRunning(app.processIdentifier)
    }

    /// 調べ終えた結果で見張りを始める。AX へは問い合わせない。
    @discardableResult
    func begin(app: InsertionTarget, lookedUp result: OpeningTargetLookupResult) -> InsertionTargetStart {
        end()
        self.app = app
        isWatching = true
        var didQuery = false
        let resolution = adopt(result.probe, of: app, didQuery: &didQuery)
        applySlowBackoff(for: result)
        outline.update(resolution.outline)
        startClickMonitor()
        startPolling()
        return InsertionTargetStart(
            target: resolution.target,
            focus: ObservedFocus(processIdentifier: app.processIdentifier, probe: result.probe)
        )
    }

    /// 調べの終わりを待たずに見張りを始める。挿入先は答えが届くまで決めない。
    func beginPending(app: InsertionTarget) -> InsertionTargetLookupToken {
        end()
        self.app = app
        isWatching = true
        nextTokenValue += 1
        let token = InsertionTargetLookupToken(value: nextTokenValue)
        pendingToken = token
        outline.update(nil)
        startClickMonitor()
        startPolling()
        return token
    }

    /// 遅れて届いた答えを反映する。番号が今の待ちのものでなければ何もしない。
    func finishPending(_ token: InsertionTargetLookupToken, result: OpeningTargetLookupResult) {
        guard isWatching, panelModel.isPresented, pendingToken == token, let app else { return }
        pendingToken = nil
        var didQuery = false
        let resolution = adopt(result.probe, of: app, didQuery: &didQuery)
        panelModel.finishTargetLookup(resolution.target)
        outline.update(resolution.outline)
        applySlowBackoff(for: result)
    }

    /// 開くときの答えを待っているか。
    var isAwaitingOpeningLookup: Bool { pendingToken != nil }

    /// 見張りをやめ、枠線の場所を消す。
    func end() {
        isWatching = false
        pollTask?.cancel()
        pollTask = nil
        recheckTask?.cancel()
        recheckTask = nil
        if let clickMonitor {
            removeClickMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        app = nil
        field = nil
        hasReadableFrame = false
        slowUntil = nil
        pendingToken = nil
        outline.update(nil)
    }

    // MARK: - 位置の追従

    /// 定期の調べ1回分。挿入先の入力欄の位置だけを読み、枠線を動かす。入力欄が使えなくなったときだけ挿入先なしにする。
    func refresh() {
        guard isWatching, pendingToken == nil else { return }
        if let slowUntil, slowUntil > now() { return }
        let resolution = measured { trackField(didQuery: &$0) }
        panelModel.updateTarget(resolution.target)
        outline.update(resolution.outline)
    }

    /// 覚えている入力欄の位置を今1回読み、まだ使える入力欄かを返す。
    func isTrackedFieldReadable() -> Bool {
        guard isWatching, let field else { return false }
        return probe.frame(of: field) != nil || !hasReadableFrame
    }

    /// 他のアプリでマウスが離されたときの処理。
    func handleClick() {
        guard isWatching else { return }
        let location = mouseLocation()
        recheckTask?.cancel()
        recheckTask = nil
        if adoptClickedField(at: location) {
            onFieldAdopted?()
            return
        }
        let sleep = self.sleep
        recheckTask = Task { @MainActor [weak self] in
            await sleep(Self.clickRecheckDelay)
            guard !Task.isCancelled, let self, self.isWatching else { return }
            if self.adoptClickedField(at: location) {
                self.onFieldAdopted?()
            }
        }
    }

    /// 今の入力欄を、選び直されるまで挿入先にしない。
    func rejectCurrentField() {
        if let app, app.isOwnApp(ownProcessIdentifier) {
            self.app = nil
        }
        clearField()
    }

    private func clearField() {
        pendingToken = nil
        field = nil
        hasReadableFrame = false
        panelModel.updateTarget(nil)
        outline.update(nil)
    }

    // MARK: - クリックでの選び直し

    private func adoptClickedField(at location: CGPoint) -> Bool {
        guard let front = frontmostApplication(), !front.isOwnApp(ownProcessIdentifier) else { return false }
        let result = probe.probeFocusedElement(in: front, readsFrame: true)
        guard let element = result.element,
              FocusedTextInputState.classifyForInsertion(result.lookup, bundleIdentifier: front.bundleIdentifier) == .textInput
        else {
            if front.processIdentifier == app?.processIdentifier {
                clearField()
            }
            return false
        }
        if let frame = result.frame {
            let point = AutoShowDecision.accessibilityPoint(fromCocoa: location, primaryScreenFrame: primaryScreenFrame())
            guard frame.contains(point) else { return false }
        }
        let isNewApp = app?.processIdentifier != front.processIdentifier
        app = front
        field = element
        hasReadableFrame = result.frame != nil
        slowUntil = nil
        pendingToken = nil
        if isNewApp {
            exposeWebContent(front)
        }
        panelModel.updateTarget(front)
        var didQuery = false
        outline.update(outlineRect(for: front, fieldFrame: result.frame, didQuery: &didQuery))
        return true
    }

    // MARK: - 挿入先の決定

    private func measured(_ body: (inout Bool) -> Resolution) -> Resolution {
        var didQuery = false
        let startedAt = now()
        let resolution = body(&didQuery)
        if didQuery {
            let finishedAt = now()
            if finishedAt.timeIntervalSince(startedAt) > Self.slowQueryThreshold {
                slowUntil = finishedAt.addingTimeInterval(Self.slowQueryBackoff)
            }
        }
        return resolution
    }

    private func resolveAtOpen(observedFocus: ObservedFocus?, didQuery: inout Bool) -> Resolution {
        guard let app else {
            field = nil
            return Resolution()
        }
        if app.isOwnApp(ownProcessIdentifier) {
            field = nil
            return (isOwnTargetAvailable?() ?? true) ? Resolution(target: app) : Resolution()
        }
        guard isRunning(app.processIdentifier) else {
            self.app = nil
            field = nil
            return Resolution()
        }

        var result: FocusedElementProbe
        if let observedFocus, observedFocus.processIdentifier == app.processIdentifier {
            result = observedFocus.probe
            if isOutlineEnabled(), result.frame == nil, let element = result.element, isTextInput(result.lookup, of: app) {
                didQuery = true
                result = FocusedElementProbe(element: element, lookup: result.lookup, frame: probe.frame(of: element))
            }
        } else {
            didQuery = true
            result = probe.probeFocusedElement(in: app, readsFrame: true)
        }
        return adopt(result, of: app, didQuery: &didQuery)
    }

    private func adopt(_ probe: FocusedElementProbe, of app: InsertionTarget, didQuery: inout Bool) -> Resolution {
        let focus = ObservedFocus(processIdentifier: app.processIdentifier, probe: probe)

        guard let element = probe.element, isTextInput(probe.lookup, of: app) else {
            field = nil
            return Resolution(focus: focus)
        }
        field = element
        hasReadableFrame = probe.frame != nil
        let rect = outlineRect(for: app, fieldFrame: probe.frame, didQuery: &didQuery)
        return Resolution(target: app, outline: rect, focus: focus)
    }

    private func applySlowBackoff(for result: OpeningTargetLookupResult) {
        if result.didQuery && result.duration > Self.slowQueryThreshold {
            slowUntil = now().addingTimeInterval(Self.slowQueryBackoff)
        }
    }

    private func trackField(didQuery: inout Bool) -> Resolution {
        guard let app else { return Resolution() }
        if app.isOwnApp(ownProcessIdentifier) {
            return (isOwnTargetAvailable?() ?? true) ? Resolution(target: app) : Resolution()
        }
        guard isRunning(app.processIdentifier) else {
            self.app = nil
            field = nil
            hasReadableFrame = false
            return Resolution()
        }
        guard let field else { return Resolution() }

        didQuery = true
        let frame = probe.frame(of: field)
        if frame == nil, hasReadableFrame {
            self.field = nil
            hasReadableFrame = false
            return Resolution()
        }
        if frame != nil {
            hasReadableFrame = true
        }
        let rect = outlineRect(for: app, fieldFrame: frame, didQuery: &didQuery)
        return Resolution(target: app, outline: rect)
    }

    private func outlineRect(for app: InsertionTarget, fieldFrame: CGRect?, didQuery: inout Bool) -> CGRect? {
        guard isOutlineEnabled(), let fieldFrame else { return nil }
        didQuery = true
        return InsertionTargetOutlineGeometry.outlineRect(
            fieldFrame: fieldFrame,
            targetProcessIdentifier: app.processIdentifier,
            ownProcessIdentifier: ownProcessIdentifier,
            windows: onScreenWindows()
        )
    }

    private func isTextInput(_ lookup: FocusedElementLookup, of app: InsertionTarget) -> Bool {
        FocusedTextInputState.classifyForInsertion(lookup, bundleIdentifier: app.bundleIdentifier) == .textInput
    }

    // MARK: - 定期の調べとクリックの見張り

    private func startPolling() {
        guard pollsAutomatically else { return }
        let sleep = self.sleep
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await sleep(Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    private func startClickMonitor() {
        clickMonitor = addClickMonitor { [weak self] in
            self?.handleClick()
        }
    }

    // MARK: - パネルが閉じたら止める

    private func observePanelDismissal() {
        observeRepeatedly(
            tracking: { [weak self] in
                _ = self?.panelModel.isPresented
            },
            onChange: { [weak self] in
                guard let self else { return false }
                if !self.panelModel.isPresented {
                    self.end()
                }
                return true
            }
        )
    }
}
