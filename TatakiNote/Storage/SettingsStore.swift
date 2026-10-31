import Foundation

/// 利用者の設定の保存と読み込み。
struct SettingsStore {
    /// 保存のキー。
    enum Key {
        static let commitKey = "commitKey"
        static let commitAndSendKey = "commitAndSendKey"
        static let commitShortcut = "commitShortcut"
        static let commitAndSendShortcut = "commitAndSendShortcut"
        static let panelScreen = "panelScreen"
        static let autoShowMode = "autoShowMode"
        static let autoShowApps = "autoShowApps"
        static let appTheme = "appTheme"
        static let panelFontName = "panelFontName"
        static let panelFontFamilyName = "panelFontFamilyName"
        static let panelFontSize = "panelFontSize"
        static let panelOpacity = "panelOpacity"
        static let hiddenPanelStatusItems = "hiddenPanelStatusItems"
        static let hidesMenuBarIcon = "hidesMenuBarIcon"
        static let panelDefaultWidth = "panelDefaultWidth"
        static let panelDefaultHeight = "panelDefaultHeight"
        static let hasShownFirstLaunchTutorial = "hasShownFirstLaunchTutorial"
        static let sidebarIsOpen = "sidebarIsOpen"
        static let sidebarTab = "sidebarTab"
        static let animationMode = "animationMode"
        static let insertionTargetOutlineShown = "insertionTargetOutlineShown"
        static let newDraftMode = "newDraftMode"
        static let historyLimit = "historyLimit"
        static let historyRetention = "historyRetention"
        static let showsDockIcon = "showsDockIcon"
        static let confirmsQuit = "confirmsQuit"
        static let lastExportDirectory = "lastExportDirectory"
        static let checksForUpdatesAutomatically = "checksForUpdatesAutomatically"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let suppressesMoveToApplicationsPrompt = "suppressesMoveToApplicationsPrompt"
    }

    let defaults: any SettingsStorage

    // MARK: - 定義による読み書き

    /// 定義に従って値を読む。無い・読めない値は定義の初期値。
    func value<Value>(_ definition: SettingDefinition<Value>) -> Value { definition.read(defaults) }

    /// 定義に従って、値を直してから保存する。
    func set<Value>(_ value: Value, for definition: SettingDefinition<Value>) {
        definition.write(definition.normalized(value), defaults)
    }

    /// オブジェクトのプロパティを定義に従って直し、直した値が違えば書き戻してから保存する。
    func persist<Root: AnyObject, Value>(
        _ keyPath: ReferenceWritableKeyPath<Root, Value>, of object: Root, as definition: SettingDefinition<Value>
    ) {
        let normalized = definition.normalized(object[keyPath: keyPath])
        if normalized != object[keyPath: keyPath] {
            object[keyPath: keyPath] = normalized
        }
        set(object[keyPath: keyPath], for: definition)
    }

    // MARK: - 確定+挿入キー・確定+送信キー

    func loadCommitShortcut() -> PanelShortcut? { value(SettingDefinitions.commitKey) }

    func saveCommitShortcut(_ shortcut: PanelShortcut?) { set(shortcut, for: SettingDefinitions.commitKey) }

    func loadCommitAndSendShortcut() -> PanelShortcut? { value(SettingDefinitions.commitAndSendKey) }

    func saveCommitAndSendShortcut(_ shortcut: PanelShortcut?) {
        set(shortcut, for: SettingDefinitions.commitAndSendKey)
    }

    // MARK: - モード

    func loadNewDraftMode() -> DraftMode { value(SettingDefinitions.newDraftMode) }

    func saveNewDraftMode(_ mode: DraftMode) { set(mode, for: SettingDefinitions.newDraftMode) }

    func loadPanelScreen() -> PanelScreen { value(SettingDefinitions.panelScreen) }

    func savePanelScreen(_ panelScreen: PanelScreen) { set(panelScreen, for: SettingDefinitions.panelScreen) }

    func loadAutoShowMode() -> AutoShowMode { value(SettingDefinitions.autoShowMode) }

    func saveAutoShowMode(_ mode: AutoShowMode) { set(mode, for: SettingDefinitions.autoShowMode) }

    func loadAutoShowApps() -> [AutoShowApp] { value(SettingDefinitions.autoShowApps) }

    func saveAutoShowApps(_ apps: [AutoShowApp]) { set(apps, for: SettingDefinitions.autoShowApps) }

    // MARK: - テーマ

    func loadAppTheme() -> AppTheme { value(SettingDefinitions.theme) }

    func saveAppTheme(_ theme: AppTheme) { set(theme, for: SettingDefinitions.theme) }

    // MARK: - パネルの文字と透明度

    func loadPanelFontName() -> String? { value(SettingDefinitions.panelFontName) }

    func savePanelFontName(_ name: String?) { set(name, for: SettingDefinitions.panelFontName) }

    /// パネルの入力欄のフォントのファミリー名を読む。無い・空・文字列でない値は `nil`。
    func loadPanelFontFamilyName() -> String? { value(SettingDefinitions.panelFontFamilyName) }

    /// パネルの入力欄のフォントのファミリー名を保存する。`nil`・空文字ならキーを消す。
    func savePanelFontFamilyName(_ name: String?) { set(name, for: SettingDefinitions.panelFontFamilyName) }

    func loadPanelFontSize() -> Double { value(SettingDefinitions.panelFontSize) }

    func savePanelFontSize(_ size: Double) { set(size, for: SettingDefinitions.panelFontSize) }

    func loadPanelOpacity() -> Double { value(SettingDefinitions.panelOpacity) }

    func savePanelOpacity(_ opacity: Double) { set(opacity, for: SettingDefinitions.panelOpacity) }

    // MARK: - 帯の項目

    func loadHiddenPanelStatusItems() -> Set<PanelStatusItem> { value(SettingDefinitions.hiddenPanelStatusItems) }

    func saveHiddenPanelStatusItems(_ items: Set<PanelStatusItem>) {
        set(items, for: SettingDefinitions.hiddenPanelStatusItems)
    }

    // MARK: - メニューバーのアイコン

    func loadHidesMenuBarIcon() -> Bool { !value(SettingDefinitions.isMenuBarIconShown) }

    func saveHidesMenuBarIcon(_ hides: Bool) { set(!hides, for: SettingDefinitions.isMenuBarIconShown) }

    // MARK: - アニメーション

    func loadAnimationMode() -> AnimationMode { value(SettingDefinitions.animationMode) }

    func saveAnimationMode(_ mode: AnimationMode) { set(mode, for: SettingDefinitions.animationMode) }

    // MARK: - 挿入先の枠線

    func loadIsInsertionTargetOutlineShown() -> Bool { value(SettingDefinitions.isInsertionTargetOutlineShown) }

    func saveIsInsertionTargetOutlineShown(_ isShown: Bool) {
        set(isShown, for: SettingDefinitions.isInsertionTargetOutlineShown)
    }

    // MARK: - Dock のアイコン

    func loadShowsDockIcon() -> Bool { value(SettingDefinitions.showsDockIcon) }

    func saveShowsDockIcon(_ shows: Bool) { set(shows, for: SettingDefinitions.showsDockIcon) }

    // MARK: - 終了の確かめ

    func loadConfirmsQuit() -> Bool { value(SettingDefinitions.confirmsQuit) }

    func saveConfirmsQuit(_ confirms: Bool) { set(confirms, for: SettingDefinitions.confirmsQuit) }

    // MARK: - アップデート

    func loadChecksForUpdatesAutomatically() -> Bool { value(SettingDefinitions.checksForUpdatesAutomatically) }

    func saveChecksForUpdatesAutomatically(_ checks: Bool) {
        set(checks, for: SettingDefinitions.checksForUpdatesAutomatically)
    }

    /// 前回アップデートを確かめた日時を読む。無い・数値でない・有限でない値は nil。
    func loadLastUpdateCheckDate() -> Date? { value(SettingDefinitions.lastUpdateCheckDate) }

    func saveLastUpdateCheckDate(_ date: Date?) { set(date, for: SettingDefinitions.lastUpdateCheckDate) }

    func loadSuppressesMoveToApplicationsPrompt() -> Bool { value(SettingDefinitions.suppressesMoveToApplicationsPrompt) }

    func saveSuppressesMoveToApplicationsPrompt(_ suppresses: Bool) {
        set(suppresses, for: SettingDefinitions.suppressesMoveToApplicationsPrompt)
    }

    // MARK: - 書き出し

    /// 前回書き出したフォルダのパスを読む。無い・文字列でない・空文字は nil。
    func loadLastExportDirectoryPath() -> String? { value(SettingDefinitions.lastExportDirectoryPath) }

    func saveLastExportDirectoryPath(_ path: String?) { set(path, for: SettingDefinitions.lastExportDirectoryPath) }

    // MARK: - 初回起動のチュートリアル

    func loadHasShownFirstLaunchTutorial() -> Bool { value(SettingDefinitions.hasShownFirstLaunchTutorial) }

    func saveHasShownFirstLaunchTutorial(_ shown: Bool) {
        set(shown, for: SettingDefinitions.hasShownFirstLaunchTutorial)
    }

    // MARK: - サイドバー

    func loadSidebarIsOpen() -> Bool { value(SettingDefinitions.isSidebarOpen) }

    func saveSidebarIsOpen(_ isOpen: Bool) { set(isOpen, for: SettingDefinitions.isSidebarOpen) }

    func loadSidebarTab() -> SidebarTab { value(SettingDefinitions.sidebarTab) }

    func saveSidebarTab(_ tab: SidebarTab) { set(tab, for: SettingDefinitions.sidebarTab) }

    // MARK: - 履歴の上限

    /// 履歴に残す件数の上限を読む。数値でない・無い・有限でない値は初期値、範囲外は端に丸める。
    func loadHistoryLimit() -> Int { value(SettingDefinitions.historyLimit) }

    func saveHistoryLimit(_ limit: Int) { set(limit, for: SettingDefinitions.historyLimit) }

    // MARK: - 履歴を残す期間

    /// 履歴を残す期間を読む。無い・文字列でない・知らない値は無期限。
    func loadHistoryRetention() -> HistoryRetention { value(SettingDefinitions.historyRetention) }

    func saveHistoryRetention(_ retention: HistoryRetention) { set(retention, for: SettingDefinitions.historyRetention) }

    // MARK: - パネルの既定の大きさ

    func loadPanelDefaultWidth() -> Double { value(SettingDefinitions.panelDefaultWidth) }

    func savePanelDefaultWidth(_ width: Double) { set(width, for: SettingDefinitions.panelDefaultWidth) }

    func loadPanelDefaultHeight() -> Double { value(SettingDefinitions.panelDefaultHeight) }

    func savePanelDefaultHeight(_ height: Double) { set(height, for: SettingDefinitions.panelDefaultHeight) }
}
