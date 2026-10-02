import AppKit
import SwiftUI

/// アクセシビリティの許可の案内のウィンドウ。
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    let model: PermissionGuideModel

    private let settings: AppSettings
    private var window: NSWindow?
    private var refreshTimer: Timer?

    var onProceedToTutorial: (() -> Void)?

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

    /// 「次へ」で案内を閉じて、チュートリアルを開く処理を呼ぶ。
    func proceedToTutorial() {
        close()
        onProceedToTutorial?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.allowsClosing
    }

    func windowWillClose(_ notification: Notification) {
        stopRefreshing()
        model.dismiss()
    }

    /// 窓の閉じるボタンを、案内が閉じてよい状態かどうかに合わせる。
    func updateClosability(of window: NSWindow) {
        let styleMask = Self.styleMask(allowsClosing: model.allowsClosing)
        if window.styleMask != styleMask {
            window.styleMask = styleMask
        }
        window.standardWindowButton(.closeButton)?.isHidden = !model.allowsClosing
    }

    static func styleMask(allowsClosing: Bool) -> NSWindow.StyleMask {
        allowsClosing ? [.titled, .closable] : [.titled]
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
        updateClosability(of: window)
        startRefreshing()
    }

    func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: Self.styleMask(allowsClosing: model.allowsClosing),
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
                onClose: { [weak self] in self?.close() },
                onProceed: { [weak self] in self?.proceedToTutorial() }
            )
        )
        return window
    }

    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.refresh()
                if let window = self.window {
                    self.updateClosability(of: window)
                }
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
    let onProceed: () -> Void

    var body: some View {
        PermissionGuideView(model: model, onClose: onClose, onProceed: onProceed)
            .windowStyle(theme: settings.theme)
    }
}
