import AppKit
import SwiftUI

/// @note p0-533
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model = SettingsWindowModel()

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginModel
    private let appInfo: AppInfoModel
    private let panelDefaultSize: PanelDefaultSizeModel
    private var window: NSWindow?

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginModel,
        appInfo: AppInfoModel,
        panelDefaultSize: PanelDefaultSizeModel
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.appInfo = appInfo
        self.panelDefaultSize = panelDefaultSize
        super.init()
    }

    /// @note p0-534
    func show() {
        if window?.isVisible != true {
            model.prepareForOpen()
        }
        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            window = makeWindow()
            self.window = window
            // @note p0-535
            window.setContentSize(SettingsView.windowSize)
            window.center()
        }
        // @note p0-536
        launchAtLogin.refresh()
        // @note p0-537
        appInfo.permissionStatus.refresh()
        // @note p0-538
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // @note p0-539
        window.orderFrontRegardless()
    }

    // @note p0-540
    func windowDidBecomeKey(_ notification: Notification) {
        launchAtLogin.refresh()
    }

    // @note p0-541
    func windowWillClose(_ notification: Notification) {
        model.prepareForOpen()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "TatakiNote の設定")
        // @note p0-542
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                model: model,
                launchAtLogin: launchAtLogin,
                appInfo: appInfo,
                panelDefaultSize: panelDefaultSize,
                onQuit: { NSApp.terminate(nil) }
            )
        )
        return window
    }
}
