import AppKit
import SwiftUI

/// 設定画面のウィンドウ。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model = SettingsWindowModel()
    let history: HistorySettingsModel

    /// 設定ウィンドウが閉じた後に呼ぶ処理。
    var onDidClose: (() -> Void)?

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginModel
    private let appInfo: AppInfoModel
    private let panelDefaultSize: PanelDefaultSizeModel
    private let library: DraftLibrary
    private let updates: UpdateModel
    private var window: NSWindow?

    private(set) lazy var fontPanel = FontPanelController(settings: settings)

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginModel,
        appInfo: AppInfoModel,
        panelDefaultSize: PanelDefaultSizeModel,
        library: DraftLibrary = DraftLibrary(store: .inMemory),
        updates: UpdateModel? = nil
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.appInfo = appInfo
        self.panelDefaultSize = panelDefaultSize
        self.library = library
        self.updates = updates ?? UpdateModel.inert(settings: settings)
        self.history = HistorySettingsModel(library: library, settings: settings)
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

    /// 設定画面が見えているときだけ、前に出し直す。
    func bringToFrontIfVisible() {
        guard let window, window.isVisible else { return }
        AppWindow.bringToFront(window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        launchAtLogin.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        model.prepareForOpen()
        history.resetPhase()
        fontPanel.close()
        DispatchQueue.main.async { [weak self] in
            self?.onDidClose?()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = AppWindow.make(
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
                library: library,
                history: history,
                updates: updates,
                onShowFontPanel: { [weak self] in self?.fontPanel.show() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        return window
    }
}
