import AppKit
import SwiftUI

/// 記録中のキー入力とクリックを見張る、見えない `NSView`。クリックは取らない。
struct ShortcutRecordingMonitor: NSViewRepresentable {
    let isRecording: Bool
    let onRecord: (PanelShortcutCandidate) -> Bool
    let onClear: () -> Void
    let onEndRecording: () -> Void

    func makeNSView(context: Context) -> ShortcutRecordingMonitorView {
        ShortcutRecordingMonitorView()
    }

    func updateNSView(_ view: ShortcutRecordingMonitorView, context: Context) {
        view.onRecord = onRecord
        view.onClear = onClear
        view.onEndRecording = onEndRecording
        view.setRecording(isRecording)
    }

    static func dismantleNSView(_ view: ShortcutRecordingMonitorView, coordinator: ()) {
        view.finishRecording()
    }
}

/// `ShortcutRecordingMonitor` の中身。
final class ShortcutRecordingMonitorView: NSView {
    var onRecord: ((PanelShortcutCandidate) -> Bool)?
    var onClear: (() -> Void)?
    var onEndRecording: (() -> Void)?

    private var localMonitor: Any?

    private static let recordingViews = NSHashTable<ShortcutRecordingMonitorView>.weakObjects()

    /// どこかの記録欄が記録中か。
    static var isRecordingAnywhere: Bool {
        !recordingViews.allObjects.isEmpty
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setRecording(_ isRecording: Bool) {
        if isRecording {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func finishRecording() {
        guard localMonitor != nil else { return }
        stopMonitoring()
        onEndRecording?()
    }

    private func startMonitoring() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleMonitoredEvent(event)
        }
        Self.recordingViews.add(self)
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        Self.recordingViews.remove(self)
    }

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
            return nil
        case .leftMouseDown, .rightMouseDown:
            handleClick(event)
            return event
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch PanelShortcutRecorderInput.action(keyCode: keyCode, modifiers: modifiers) {
        case .cancel:
            finishRecording()
        case .clear:
            onClear?()
            finishRecording()
        case .record:
            let candidate = PanelShortcutCandidate(
                shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers),
                characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
            )
            if onRecord?(candidate) == true {
                finishRecording()
            } else {
                NSSound.beep()
            }
        }
    }

    private func handleClick(_ event: NSEvent) {
        let isSameWindow = event.window != nil && event.window === window
        let location = isSameWindow ? convert(event.locationInWindow, from: nil) : .zero
        if PanelShortcutRecorderInput.isOutsideClick(location: location, recorderBounds: bounds, isSameWindow: isSameWindow) {
            finishRecording()
        }
    }

    @objc private func windowDidResignKey() {
        finishRecording()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if newWindow == nil {
            finishRecording()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window
            )
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
