import AppKit
import SwiftUI

/// 設定画面のウィンドウ。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model = SettingsWindowModel()

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginModel
    private let appInfo: AppInfoModel
    private let panelDefaultSize: PanelDefaultSizeModel
    private var window: NSWindow?

    private(set) lazy var fontPanel = FontPanelController(settings: settings)

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
            window.setContentSize(SettingsView.windowSize)
            window.center()
        }
        launchAtLogin.refresh()
        appInfo.permissionStatus.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        launchAtLogin.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        model.prepareForOpen()
        fontPanel.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "TatakiNote の設定")
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
                onShowFontPanel: { [weak self] in self?.fontPanel.show() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        return window
    }
}
