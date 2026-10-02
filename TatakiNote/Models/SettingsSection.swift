/// 設定画面のサイドバーの項目。
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case editor
    case appInfo

    var id: Self { self }
}
