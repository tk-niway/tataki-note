import AppKit

/// 見張りから渡すイベント。
struct PanelPointerEvent: Equatable {
    /// イベントの種類。
    enum Kind: Equatable {
        case moved, modifiersChanged, buttonDown, dragged

        /// NSEvent の種類を振り分ける。見張りのマスクに無い種類は nil。
        init?(eventType: NSEvent.EventType) {
            switch eventType {
            case .mouseMoved: self = .moved
            case .flagsChanged: self = .modifiersChanged
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: self = .buttonDown
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: self = .dragged
            default: return nil
            }
        }
    }

    var kind: Kind
    var modifierFlags: NSEvent.ModifierFlags
}

/// カーソルの動き・修飾キー・マウスボタンのイベントを見張る。
protocol PanelPointerEventMonitoring: AnyObject {
    /// 見張りを始める。始めていれば何もしない。
    func start(_ handler: @escaping (PanelPointerEvent) -> Void)
    /// 見張りをやめる。
    func stop()
}

/// NSEvent のグローバルとローカルの見張り。ローカルはイベントをそのまま返す(消費しない)。
final class NSEventPanelPointerEventMonitor: PanelPointerEventMonitoring {
    private static let mask: NSEvent.EventTypeMask = [
        .mouseMoved, .flagsChanged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(_ handler: @escaping (PanelPointerEvent) -> Void) {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { event in
            MainActor.assumeIsolated {
                Self.deliver(event, to: handler)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { event in
            Self.deliver(event, to: handler)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private static func deliver(_ event: NSEvent, to handler: (PanelPointerEvent) -> Void) {
        if let kind = PanelPointerEvent.Kind(eventType: event.type) {
            handler(PanelPointerEvent(kind: kind, modifierFlags: event.modifierFlags))
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

/// 修飾キーを押したままのカーソルの動きで、パネルを動かし・大きさを変える。
final class PanelPointerController {
    private let panel: NSWindow
    private let settings: AppSettings
    private let monitor: PanelPointerEventMonitoring
    private let availability: () -> PanelPointerAvailability
    private let willBegin: () -> Void
    private let didResize: (CGSize, CGSize) -> Void
    private let mouseLocation: () -> CGPoint
    private let isMouseButtonPressed: () -> Bool
    private let screenTopLimit: (CGPoint) -> CGFloat?
    private let currentModifierFlags: () -> NSEvent.ModifierFlags
    private var gesture = PanelPointerGesture()

    init(
        panel: NSWindow,
        settings: AppSettings,
        monitor: PanelPointerEventMonitoring,
        availability: @escaping () -> PanelPointerAvailability,
        willBegin: @escaping () -> Void,
        didResize: @escaping (_ from: CGSize, _ to: CGSize) -> Void,
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        isMouseButtonPressed: @escaping () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        screenTopLimit: @escaping (CGPoint) -> CGFloat? = { point in
            PanelPointerFrame.screenTopLimit(at: point, screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        },
        currentModifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.panel = panel
        self.settings = settings
        self.monitor = monitor
        self.availability = availability
        self.willBegin = willBegin
        self.didResize = didResize
        self.mouseLocation = mouseLocation
        self.isMouseButtonPressed = isMouseButtonPressed
        self.screenTopLimit = screenTopLimit
        self.currentModifierFlags = currentModifierFlags
    }

    /// 今の状態。
    var state: PanelPointerGesture.State { gesture.state }

    /// 今押している修飾キーをパネルの外で押したものとして、見張りを始める。
    func start() {
        gesture.reset(heldModifiers: PanelPointerModifier.set(from: currentModifierFlags()))
        monitor.start { [weak self] event in
            self?.handle(event)
        }
    }

    /// 動かしている途中なら止め、見張りをやめる。
    func stop() {
        gesture.reset()
        monitor.stop()
    }

    /// イベントを1つ処理する。
    func handle(_ event: PanelPointerEvent) {
        let modifiers = PanelPointerModifier.set(from: event.modifierFlags)
        let isButtonPressed = event.kind == .buttonDown
            || event.kind == .dragged
            || (event.kind == .modifiersChanged && isMouseButtonPressed())
        let moveModifiers = settings.pointerModifiers(for: .move)
        let resizeModifiers = settings.pointerModifiers(for: .resize)

        if gesture.state == .idle, modifiers == gesture.press.modifiers {
            let matchesMove = !moveModifiers.isEmpty && modifiers == moveModifiers
            let matchesResize = !resizeModifiers.isEmpty && modifiers == resizeModifiers
            guard gesture.press.isOverPanel, matchesMove || matchesResize else { return }
        }

        let pointer = mouseLocation()
        let availability = availability()
        let sample = PanelPointerSample(pointer: pointer, modifiers: modifiers, isMouseButtonPressed: isButtonPressed)
        let context = PanelPointerContext(
            panelFrame: panel.frame,
            isPanelShown: availability.isPanelShown,
            isSidebarSliding: availability.isSidebarSliding,
            isSidebarOpen: availability.isSidebarOpen,
            moveModifiers: moveModifiers,
            resizeModifiers: resizeModifiers,
            screenTopLimit: screenTopLimit(pointer)
        )

        switch gesture.handle(sample, in: context) {
        case .none:
            break
        case .begin(let action):
            willBegin()
            gesture.begin(action, pointer: pointer, frame: panel.frame, isSidebarOpen: availability.isSidebarOpen)
        case .setOrigin(let origin):
            panel.setFrameOrigin(origin)
        case .setFrame(let frame):
            let oldSize = panel.frame.size
            panel.setFrame(frame, display: true)
            didResize(oldSize, panel.frame.size)
        }
    }
}
