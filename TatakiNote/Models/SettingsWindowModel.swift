import Observation

/// 設定画面の状態(サイドバーで選んでいる項目)。
@Observable final class SettingsWindowModel {
    var selectedSection: SettingsSection = .general

    @ObservationIgnored private let hotkey: () -> PanelShortcut?

    init(hotkey: @escaping () -> PanelShortcut? = PanelShortcut.currentHotkey) {
        self.hotkey = hotkey
    }

    func prepareForOpen() {
        selectedSection = .general
    }

    /// 注入したホットキーを使って、設定のモードを切り替える。
    func selectAppMode(_ mode: AppMode, in settings: AppSettings) {
        settings.selectAppMode(mode, hotkey: hotkey())
    }
}
