import AppKit
import Observation

/// Mac 標準のフォントパネルと設定のフォントをつなぐ。
final class FontPanelController: NSObject, NSFontChanging {
    static let panelIdentifier = "fontPanel"

    private let settings: AppSettings
    private let fontManager: NSFontManager

    /// フォントパネルからの変更を受け取っているとき true。
    private(set) var isActive = false
    /// 設定の変化を追いかけているとき true。
    private(set) var isObserving = false

    init(settings: AppSettings, fontManager: NSFontManager = .shared) {
        self.settings = settings
        self.fontManager = fontManager
        super.init()
    }

    /// 今の設定のフォントを選んだ状態でフォントパネルを前面に出す。
    func show() {
        activate()
        fontManager.fontPanel(true)?.setAccessibilityIdentifier(Self.panelIdentifier)
        fontManager.orderFrontFontPanel(self)
    }

    /// フォントパネルからの変更をこのコントローラーで受け取り、設定の変化を追いかけ始める。
    func activate() {
        isActive = true
        fontManager.target = self
        syncSelectedFont()
        if !isObserving {
            observeSettings()
        }
    }

    /// フォントパネルで選ばれているフォントを設定のフォントに合わせる。
    func syncSelectedFont() {
        fontManager.setSelectedFont(settings.panelFont, isMultiple: false)
    }

    /// フォントパネルでの変更を設定に入れる。
    func changeFont(_ sender: NSFontManager?) {
        guard isActive, let sender else { return }
        apply { sender.convert($0) }
    }

    /// 今の設定のフォントを `convert` で変換した結果を設定に入れる。
    func apply(convertedBy convert: (NSFont) -> NSFont) {
        settings.selectPanelFont(convert(settings.panelFont))
    }

    /// フォントパネルに出す部品を、書体・太さ・サイズに絞る。
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }

    /// フォントパネルを閉じ、変更の受け取りをやめる。
    func close() {
        guard isActive else { return }
        fontManager.fontPanel(false)?.orderOut(nil)
        if fontManager.target === self {
            fontManager.target = nil
        }
        isActive = false
    }

    private func observeSettings() {
        isObserving = true
        withObservationTracking {
            _ = settings.panelFont
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.settingsDidChange()
            }
        }
    }

    private func settingsDidChange() {
        guard isActive else {
            isObserving = false
            return
        }
        syncSelectedFont()
        observeSettings()
    }
}
