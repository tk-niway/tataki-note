import AppKit
import SwiftUI

/// 確定キー・確定+送信キーの記録ボックス。
struct PanelShortcutRecorder: NSViewRepresentable {
    let displayText: String?
    let isRecording: Bool
    let isRecordingNow: () -> Bool
    let onBeginRecording: () -> Void
    let onRecord: (PanelShortcutCandidate) -> Bool
    let onClear: () -> Void
    let onEndRecording: () -> Void
    let identifier: String

    func makeNSView(context: Context) -> PanelShortcutRecorderField {
        let field = PanelShortcutRecorderField()
        field.setAccessibilityIdentifier(identifier)
        return field
    }

    func updateNSView(_ field: PanelShortcutRecorderField, context: Context) {
        field.onBeginRecording = onBeginRecording
        field.onRecord = onRecord
        field.onClear = onClear
        field.onEndRecording = onEndRecording
        field.updateDisplay(text: displayText, isRecording: isRecordingNow())
    }
}

/// `PanelShortcutRecorder` の中身。
final class PanelShortcutRecorderField: NSSearchField, NSSearchFieldDelegate {
    var onBeginRecording: (() -> Void)?
    var onRecord: ((PanelShortcutCandidate) -> Bool)?
    var onClear: (() -> Void)?
    var onEndRecording: (() -> Void)?

    private var isRecordingKeys = false
    private var isBeginningRecording = false
    private var localMonitor: Any?
    private var hasRegisteredValue = false

    private let idlePlaceholder = String(localized: "ショートカットを記録")
    private let recordingPlaceholder = String(localized: "ショートカットを押す")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        delegate = self
        menu = nil
        searchMenuTemplate = nil
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        sendsSearchStringImmediately = false
        sendsWholeSearchString = true
        recentsAutosaveName = nil
        alignment = .center
        placeholderString = idlePlaceholder
    }

    override class var cellClass: AnyClass? {
        get { PanelShortcutRecorderCell.self }
        set {}
    }

    override var acceptsFirstResponder: Bool { isRecordingKeys }
    override var canBecomeKeyView: Bool { isRecordingKeys }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let cell = cell as? PanelShortcutRecorderCell, cell.cancelButtonRect(forBounds: bounds).contains(location) {
            onClear?()
            return
        }
        beginRecordingKeys()
    }

    override func accessibilityPerformPress() -> Bool {
        beginRecordingKeys()
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    func updateDisplay(text: String?, isRecording: Bool) {
        hasRegisteredValue = text != nil
        (cell as? PanelShortcutRecorderCell)?.showsCancelButtonEvenWhenEmpty = hasRegisteredValue
        if isRecordingKeys, !isRecording, !isBeginningRecording {
            isRecordingKeys = false
            stopMonitoring()
            window?.makeFirstResponder(nil)
        }
        guard !isRecordingKeys else { return }
        stringValue = text ?? ""
        placeholderString = idlePlaceholder
    }

    private func beginRecordingKeys() {
        guard !isRecordingKeys else { return }
        isRecordingKeys = true
        isBeginningRecording = true
        defer { isBeginningRecording = false }
        onBeginRecording?()
        stringValue = ""
        placeholderString = recordingPlaceholder
        startMonitoring()
        window?.makeFirstResponder(self)
    }

    private func endRecordingKeys() {
        guard isRecordingKeys, !isBeginningRecording else { return }
        isRecordingKeys = false
        stopMonitoring()
        placeholderString = idlePlaceholder
        stringValue = ""
        window?.makeFirstResponder(nil)
        onEndRecording?()
    }

    private func startMonitoring() {
        stopMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleMonitoredEvent(event)
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecordingKeys else {
            stopMonitoring()
            return event
        }
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
            return nil
        case .leftMouseDown, .rightMouseDown:
            handleMonitoredClick(event)
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
            endRecordingKeys()
        case .clear:
            onClear?()
            endRecordingKeys()
        case .record:
            let candidate = PanelShortcutCandidate(
                shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers),
                characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
            )
            if onRecord?(candidate) == true {
                endRecordingKeys()
            } else {
                NSSound.beep()
            }
        }
    }

    private func handleMonitoredClick(_ event: NSEvent) {
        let isSameWindow = event.window === window
        let location = isSameWindow ? convert(event.locationInWindow, from: nil) : .zero
        if PanelShortcutRecorderInput.isOutsideClick(location: location, recorderBounds: bounds, isSameWindow: isSameWindow) {
            endRecordingKeys()
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endRecordingKeys()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            endRecordingKeys()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window
            )
        }
    }

    @objc private func windowDidResignKey() {
        endRecordingKeys()
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

/// 記録中に表記を消していても、登録があれば × ボタンを出すセル。
final class PanelShortcutRecorderCell: NSSearchFieldCell {
    var showsCancelButtonEvenWhenEmpty = false

    private var retainedCancelButtonCell: NSButtonCell?

    override var cancelButtonCell: NSButtonCell? {
        get {
            let current = super.cancelButtonCell
            if let current {
                retainedCancelButtonCell = current
            }
            return showsCancelButtonEvenWhenEmpty ? (current ?? retainedCancelButtonCell) : current
        }
        set { super.cancelButtonCell = newValue }
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        let standard = super.cancelButtonRect(forBounds: rect)
        guard showsCancelButtonEvenWhenEmpty, standard == .zero else { return standard }
        let size = NSSize(width: 14, height: 14)
        return NSRect(x: rect.maxX - size.width - 4, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
