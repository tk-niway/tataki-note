import AppKit
import SwiftUI

/// アクセシビリティの許可の案内のウィンドウ。
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    let model: PermissionGuideModel

    private let settings: AppSettings
    private var window: NSWindow?
    private var refreshTask: Task<Void, Never>?

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
        let window = AppWindow.prepare(
            existing: self.window,
            make: makeWindow,
            initialContentSize: { $0.contentView?.fittingSize }
        )
        self.window = window
        AppWindow.bringToFront(window)
        updateClosability(of: window)
        startRefreshing()
    }

    func makeWindow() -> NSWindow {
        let model = model
        return AppWindow.make(
            title: String(localized: "アクセシビリティの許可"),
            identifier: "permissionGuide",
            styleMask: Self.styleMask(allowsClosing: model.allowsClosing),
            delegate: self,
            rootView: ThemedWindowContent(settings: settings) {
                PermissionGuideView(
                    model: model,
                    onClose: { [weak self] in self?.close() },
                    onProceed: { [weak self] in self?.proceedToTutorial() }
                )
            }
        )
    }

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self, model] in
            await model.watch {
                guard let self, let window = self.window else { return }
                self.updateClosability(of: window)
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
