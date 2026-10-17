import Observation

/// 設定画面の状態(サイドバーで選んでいる項目)。
@Observable final class SettingsWindowModel {
    var selectedSection: SettingsSection = .general

    func prepareForOpen() {
        selectedSection = .general
    }
}
