import AppKit
import Observation
import SwiftUI

/// チュートリアルのウィンドウ。
final class TutorialWindowController: NSObject, NSWindowDelegate {
    static let contentSize = NSSize(width: 520, height: 560)

    let model: TutorialModel

    private let settings: AppSettings
    private let panelModel: PanelModel
    private let ownProcessIdentifier: pid_t
    private let focusWindow: (NSWindow) -> Void
    /// 開いているチュートリアルのウィンドウ。
    private(set) var window: NSWindow?
    private var isObservingPanel = false
    private var observationGeneration = 0

    init(
        settings: AppSettings,
        panelModel: PanelModel,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        focusWindow: @escaping (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) }
    ) {
        self.settings = settings
        self.panelModel = panelModel
        self.ownProcessIdentifier = ownProcessIdentifier
        self.focusWindow = focusWindow
        self.model = TutorialModel(ownProcessIdentifier: ownProcessIdentifier, settings: settings)
        super.init()
    }

    // MARK: - 表示

    /// チュートリアルを前面に開く。見えていなければ手順1から始める。
    func show() {
        if window?.isVisible != true {
            model.reset()
        }
        let window = self.window ?? makeWindow()
        if self.window == nil {
            self.window = window
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        model.refreshKeys()
        model.requestPracticeFocus()
        startObservingPanel()
    }

    /// チュートリアルを閉じる。
    func close() {
        window?.close()
    }

    // MARK: - 挿入先

    /// 窓がキーでアプリがアクティブなら、TatakiNote 自身を挿入先として返す。
    func practiceTarget() -> InsertionTarget? {
        Self.practiceTarget(
            isWindowKey: window?.isKeyWindow == true,
            isAppActive: NSApp.isActive,
            own: InsertionTarget(NSRunningApplication.current)
        )
    }

    static func practiceTarget(isWindowKey: Bool, isAppActive: Bool, own: InsertionTarget) -> InsertionTarget? {
        isWindowKey && isAppActive ? own : nil
    }

    /// 練習用の入力欄への挿入が要求されたとき、窓を前に出して入力欄にフォーカスを戻す。
    func handleInsertionRequested(text: String, target: InsertionTarget, sendsAfterInsert: Bool) {
        guard target.processIdentifier == ownProcessIdentifier,
              let window, window.isVisible
        else { return }
        model.insertionRequested(text: text, target: target, sendsAfterInsert: sendsAfterInsert)
        focusWindow(window)
        model.requestPracticeFocus()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshKeys()
    }

    func windowWillClose(_ notification: Notification) {
        isObservingPanel = false
    }

    // MARK: - 内部

    func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "TatakiNote の使い方")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("tutorial")
        window.contentView = NSHostingView(
            rootView: TutorialRootView(
                settings: settings,
                model: model,
                onClose: { [weak self] in self?.close() }
            )
        )
        window.setContentSize(Self.contentSize)
        return window
    }

    private func startObservingPanel() {
        guard !isObservingPanel else { return }
        isObservingPanel = true
        observationGeneration += 1
        observePanel(generation: observationGeneration)
    }

    private func observePanel(generation: Int) {
        withObservationTracking {
            _ = panelModel.isPresented
            _ = panelModel.target
            _ = panelModel.text
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObservingPanel, self.observationGeneration == generation else { return }
                self.model.panelDidChange(
                    isPresented: self.panelModel.isPresented,
                    target: self.panelModel.target,
                    text: self.panelModel.text
                )
                self.observePanel(generation: generation)
            }
        }
    }
}

private struct TutorialRootView: View {
    let settings: AppSettings
    let model: TutorialModel
    let onClose: () -> Void

    var body: some View {
        TutorialView(model: model, onClose: onClose)
            .windowStyle(theme: settings.theme)
    }
}
