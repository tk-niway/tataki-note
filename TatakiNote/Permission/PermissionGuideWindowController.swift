import AppKit
import SwiftUI

/// アクセシビリティの許可の案内のウィンドウ。
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    let model: PermissionGuideModel

    private let settings: AppSettings
    private var window: NSWindow?
    private var refreshTimer: Timer?

    init(model: PermissionGuideModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        super.init()
    }

    func show(reason: PermissionGuideReason) {
        model.present(reason: reason)
        bringWindowToFront()
    }

    func showOnLaunchIfNeeded() {
        guard model.presentOnLaunchIfNeeded() else { return }
        bringWindowToFront()
    }

    func close() {
        window?.close()
    }

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
            if let contentView = window.contentView {
                window.setContentSize(contentView.fittingSize)
            }
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        startRefreshing()
    }

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
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

private struct PermissionGuideRootView: View {
    let settings: AppSettings
    let model: PermissionGuideModel
    let onClose: () -> Void

    var body: some View {
        PermissionGuideView(model: model, onClose: onClose)
            .windowStyle(theme: settings.theme)
    }
}
