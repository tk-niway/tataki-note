import AppKit
import SwiftUI

/// @note p0-520
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    let model: PermissionGuideModel

    /// @note p0-521
    private let settings: AppSettings
    private var window: NSWindow?
    /// @note p0-522
    private var refreshTimer: Timer?

    init(model: PermissionGuideModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        super.init()
    }

    /// @note p0-523
    func show(reason: PermissionGuideReason) {
        model.present(reason: reason)
        bringWindowToFront()
    }

    /// @note p0-524
    func showOnLaunchIfNeeded() {
        guard model.presentOnLaunchIfNeeded() else { return }
        bringWindowToFront()
    }

    func close() {
        window?.close()
    }

    // @note p0-525
    func windowWillClose(_ notification: Notification) {
        stopRefreshing()
        model.dismiss()
    }

    private func bringWindowToFront() {
        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            window = makeWindow()
            self.window = window
            // @note p0-526
            if let contentView = window.contentView {
                window.setContentSize(contentView.fittingSize)
            }
            window.center()
        }
        // @note p0-527
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // @note p0-528
        window.orderFrontRegardless()
        startRefreshing()
    }

    /// @note p0-529
    func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "アクセシビリティの許可")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("permissionGuide")
        // @note p0-530
        window.contentView = NSHostingView(
            rootView: PermissionGuideRootView(
                settings: settings,
                model: model,
                onClose: { [weak self] in self?.close() }
            )
        )
        return window
    }

    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refresh()
            }
        }
        // @note p0-531
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

/// @note p0-532
private struct PermissionGuideRootView: View {
    let settings: AppSettings
    let model: PermissionGuideModel
    let onClose: () -> Void

    var body: some View {
        PermissionGuideView(model: model, onClose: onClose)
            .windowStyle(theme: settings.theme)
    }
}
