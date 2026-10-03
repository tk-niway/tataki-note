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
        launchAtLogin.refresh()
        appInfo.permissionStatus.refresh()
        let window = AppWindow.prepare(
            existing: self.window,
            make: makeWindow,
            initialContentSize: { _ in SettingsView.windowSize }
        )
        self.window = window
        AppWindow.bringToFront(window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        launchAtLogin.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        model.prepareForOpen()
        fontPanel.close()
    }

    private func makeWindow() -> NSWindow {
        AppWindow.make(
            title: String(localized: "TatakiNote の設定"),
            identifier: "settings",
            styleMask: [.titled, .closable, .fullSizeContentView],
            delegate: self,
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
    }
}
