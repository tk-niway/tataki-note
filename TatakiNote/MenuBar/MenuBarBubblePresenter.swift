import AppKit
import SwiftUI

/// 吹き出しの中身。クリックを前面のアプリを変えずに受ける。
final class InsertionFailureBubbleContentView: NSView {
    static let accessibilityIdentifierValue = "insertionFailureBubble"

    var onClick: (() -> Void)?

    private let hostingView = NSHostingView(rootView: InsertionFailureBubbleView(message: ""))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(hostingView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(Self.accessibilityIdentifierValue)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// 文を入れ替えて、大きさを文に合わせる。
    func configure(message: String) {
        hostingView.rootView = InsertionFailureBubbleView(message: message)
        let size = hostingView.fittingSize
        setFrameSize(size)
        hostingView.frame = NSRect(origin: .zero, size: size)
        setAccessibilityLabel(message)
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.preventWindowOrdering()
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func accessibilityChildren() -> [Any]? { [] }
}

/// 挿入できなかったことを知らせる吹き出しを、`NSPopover` で出す。
final class MenuBarBubblePresenter: NSObject, InsertionFailureBubblePresenting, NSPopoverDelegate {
    var onClick: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var onClosedBySystem: (() -> Void)?

    private static let outsideClickEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    private var popover: NSPopover?
    private var contentView: InsertionFailureBubbleContentView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCloseRequested = false

    func show(message: String, relativeTo anchor: NSView) {
        let (popover, contentView) = makePopoverIfNeeded()
        contentView.configure(message: message)
        popover.contentSize = contentView.frame.size
        if !popover.isShown {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        startMonitoring()
    }

    func close() {
        stopMonitoring()
        guard let popover, popover.isShown else { return }
        isCloseRequested = true
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoring()
        if isCloseRequested {
            isCloseRequested = false
        } else {
            onClosedBySystem?()
        }
    }

    private func makePopoverIfNeeded() -> (NSPopover, InsertionFailureBubbleContentView) {
        if let popover, let contentView {
            return (popover, contentView)
        }
        let contentView = InsertionFailureBubbleContentView(frame: .zero)
        contentView.onClick = { [weak self] in self?.onClick?() }
        let controller = NSViewController()
        controller.view = contentView
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        self.contentView = contentView
        return (popover, contentView)
    }

    private func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.outsideClickEvents) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onOutsideClick?()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.outsideClickEvents) { [weak self] event in
            guard let self else { return event }
            let bubbleWindow = self.contentView?.window
            if bubbleWindow == nil || event.window !== bubbleWindow {
                self.onOutsideClick?()
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }
}
