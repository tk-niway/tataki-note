import AppKit
import KeyboardShortcuts
import SwiftUI

/// ⌘Q を見張り、確かめの窓を出す。
final class QuitConfirmationController: NSObject, NSWindowDelegate {
    let model: QuitConfirmationModel

    private let settings: AppSettings
    private let isRecordingShortcut: (NSEvent) -> Bool
    private let isPanelCommitKey: (NSEvent) -> Bool
    private var window: NSWindow?
    private weak var previousKeyWindow: NSWindow?
    private var keyMonitor: Any?

    init(
        model: QuitConfirmationModel,
        settings: AppSettings,
        isRecordingShortcut: @escaping (NSEvent) -> Bool,
        isPanelCommitKey: @escaping (NSEvent) -> Bool
    ) {
        self.model = model
        self.settings = settings
        self.isRecordingShortcut = isRecordingShortcut
        self.isPanelCommitKey = isPanelCommitKey
        super.init()
    }

    /// ホットキーの記録欄が編集中か。
    static func isKeyboardShortcutsRecorderFocused(in window: NSWindow?) -> Bool {
        (window?.firstResponder as? NSText)?.delegate is KeyboardShortcuts.RecorderCocoa
    }

    /// ⌘Q の見張りを始める。
    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard QuitConfirmation.isQuitKey(
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) else { return event }
        let action = model.handleQuitKey(
            isRecordingShortcut: isRecordingShortcut(event),
            isPanelCommitKey: isPanelCommitKey(event),
            isModalRunning: NSApp.modalWindow != nil
        )
        switch action {
        case .passThrough:
            return event
        case .ignore, .quit:
            return nil
        case .confirm:
            DispatchQueue.main.async { [weak self] in
                self?.present()
            }
            return nil
        }
    }

    private func present() {
        let current = NSApp.keyWindow
        previousKeyWindow = current === window ? nil : current
        let window = AppWindow.prepare(
            existing: self.window,
            make: makeWindow,
            initialContentSize: { $0.contentView?.fittingSize }
        )
        self.window = window
        window.level = .modalPanel
        AppWindow.bringToFront(window)
    }

    private func makeWindow() -> NSWindow {
        let model = model
        let onQuit: () -> Void = { [weak self] in self?.confirmQuit() }
        let onCancel: () -> Void = { [weak self] in self?.cancel() }
        let window = AppWindow.make(
            title: String(localized: "TatakiNote を終了"),
            identifier: "quitConfirmation",
            styleMask: [.titled],
            delegate: self,
            rootView: ThemedWindowContent(settings: settings) {
                QuitConfirmationView(model: model, onQuit: onQuit, onCancel: onCancel)
            }
        )
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }

    private func confirmQuit() {
        model.quit()
    }

    private func cancel() {
        model.cancel()
        window?.orderOut(nil)
        if let previousKeyWindow, previousKeyWindow.isVisible {
            previousKeyWindow.makeKeyAndOrderFront(nil)
        }
        previousKeyWindow = nil
    }
}
