import Foundation
@testable import TatakiNote

extension SettingsStore {
    /// 保存のキー(文字列で直に書く)。
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

    /// 確定+挿入キーを読む。
    func loadCommitShortcut() -> PanelShortcut? { value(SettingDefinitions.commitKey) }

    /// 確定+挿入キーを保存する。
    func saveCommitShortcut(_ shortcut: PanelShortcut?) { set(shortcut, for: SettingDefinitions.commitKey) }

    /// 確定+送信キーを読む。
    func loadCommitAndSendShortcut() -> PanelShortcut? { value(SettingDefinitions.commitAndSendKey) }

    /// 確定+送信キーを保存する。
    func saveCommitAndSendShortcut(_ shortcut: PanelShortcut?) {
        set(shortcut, for: SettingDefinitions.commitAndSendKey)
    }

    /// 新しい下書きのモードを読む。
    func loadNewDraftMode() -> DraftMode { value(SettingDefinitions.newDraftMode) }

    /// 新しい下書きのモードを保存する。
    func saveNewDraftMode(_ mode: DraftMode) { set(mode, for: SettingDefinitions.newDraftMode) }

    /// パネルを出す画面を読む。
    func loadPanelScreen() -> PanelScreen { value(SettingDefinitions.panelScreen) }

    /// パネルを出す画面を保存する。
    func savePanelScreen(_ panelScreen: PanelScreen) { set(panelScreen, for: SettingDefinitions.panelScreen) }

    /// 自動表示のモードを読む。
    func loadAutoShowMode() -> AutoShowMode { value(SettingDefinitions.autoShowMode) }

    /// 自動表示のモードを保存する。
    func saveAutoShowMode(_ mode: AutoShowMode) { set(mode, for: SettingDefinitions.autoShowMode) }

    /// 自動表示の対象のアプリを読む。
    func loadAutoShowApps() -> [AutoShowApp] { value(SettingDefinitions.autoShowApps) }

    /// 自動表示の対象のアプリを保存する。
    func saveAutoShowApps(_ apps: [AutoShowApp]) { set(apps, for: SettingDefinitions.autoShowApps) }

    /// テーマを読む。
    func loadAppTheme() -> AppTheme { value(SettingDefinitions.theme) }

    /// テーマを保存する。
    func saveAppTheme(_ theme: AppTheme) { set(theme, for: SettingDefinitions.theme) }

    /// パネルのフォント名を読む。
    func loadPanelFontName() -> String? { value(SettingDefinitions.panelFontName) }

    /// パネルのフォント名を保存する。
    func savePanelFontName(_ name: String?) { set(name, for: SettingDefinitions.panelFontName) }

    /// パネルのフォントのファミリー名を読む。
    func loadPanelFontFamilyName() -> String? { value(SettingDefinitions.panelFontFamilyName) }

    /// パネルのフォントのファミリー名を保存する。
    func savePanelFontFamilyName(_ name: String?) { set(name, for: SettingDefinitions.panelFontFamilyName) }

    /// パネルの文字の大きさを読む。
    func loadPanelFontSize() -> Double { value(SettingDefinitions.panelFontSize) }

    /// パネルの文字の大きさを保存する。
    func savePanelFontSize(_ size: Double) { set(size, for: SettingDefinitions.panelFontSize) }

    /// パネルの透明度を読む。
    func loadPanelOpacity() -> Double { value(SettingDefinitions.panelOpacity) }

    /// パネルの透明度を保存する。
    func savePanelOpacity(_ opacity: Double) { set(opacity, for: SettingDefinitions.panelOpacity) }

    /// 帯で隠す項目を読む。
    func loadHiddenPanelStatusItems() -> Set<PanelStatusItem> { value(SettingDefinitions.hiddenPanelStatusItems) }

    /// 帯で隠す項目を保存する。
    func saveHiddenPanelStatusItems(_ items: Set<PanelStatusItem>) {
        set(items, for: SettingDefinitions.hiddenPanelStatusItems)
    }

    /// メニューバーのアイコンを隠すかを読む。
    func loadHidesMenuBarIcon() -> Bool { !value(SettingDefinitions.isMenuBarIconShown) }

    /// メニューバーのアイコンを隠すかを保存する。
    func saveHidesMenuBarIcon(_ hides: Bool) { set(!hides, for: SettingDefinitions.isMenuBarIconShown) }

    /// アニメーションのモードを読む。
    func loadAnimationMode() -> AnimationMode { value(SettingDefinitions.animationMode) }

    /// アニメーションのモードを保存する。
    func saveAnimationMode(_ mode: AnimationMode) { set(mode, for: SettingDefinitions.animationMode) }

    /// 挿入先の枠線を出すかを読む。
    func loadIsInsertionTargetOutlineShown() -> Bool { value(SettingDefinitions.isInsertionTargetOutlineShown) }

    /// 挿入先の枠線を出すかを保存する。
    func saveIsInsertionTargetOutlineShown(_ isShown: Bool) {
        set(isShown, for: SettingDefinitions.isInsertionTargetOutlineShown)
    }

    /// Dock のアイコンを出すかを読む。
    func loadShowsDockIcon() -> Bool { value(SettingDefinitions.showsDockIcon) }

    /// Dock のアイコンを出すかを保存する。
    func saveShowsDockIcon(_ shows: Bool) { set(shows, for: SettingDefinitions.showsDockIcon) }

    /// 終了の確かめを出すかを読む。
    func loadConfirmsQuit() -> Bool { value(SettingDefinitions.confirmsQuit) }

    /// 終了の確かめを出すかを保存する。
    func saveConfirmsQuit(_ confirms: Bool) { set(confirms, for: SettingDefinitions.confirmsQuit) }

    /// アップデートを自動で確かめるかを読む。
    func loadChecksForUpdatesAutomatically() -> Bool { value(SettingDefinitions.checksForUpdatesAutomatically) }

    /// アップデートを自動で確かめるかを保存する。
    func saveChecksForUpdatesAutomatically(_ checks: Bool) {
        set(checks, for: SettingDefinitions.checksForUpdatesAutomatically)
    }

    /// 前回アップデートを確かめた日時を読む。
    func loadLastUpdateCheckDate() -> Date? { value(SettingDefinitions.lastUpdateCheckDate) }

    /// 前回アップデートを確かめた日時を保存する。
    func saveLastUpdateCheckDate(_ date: Date?) { set(date, for: SettingDefinitions.lastUpdateCheckDate) }

    /// 「アプリケーションフォルダへ移動」の確認を出さないかを読む。
    func loadSuppressesMoveToApplicationsPrompt() -> Bool {
        value(SettingDefinitions.suppressesMoveToApplicationsPrompt)
    }

    /// 「アプリケーションフォルダへ移動」の確認を出さないかを保存する。
    func saveSuppressesMoveToApplicationsPrompt(_ suppresses: Bool) {
        set(suppresses, for: SettingDefinitions.suppressesMoveToApplicationsPrompt)
    }

    /// 前回書き出したフォルダのパスを読む。
    func loadLastExportDirectoryPath() -> String? { value(SettingDefinitions.lastExportDirectoryPath) }

    /// 前回書き出したフォルダのパスを保存する。
    func saveLastExportDirectoryPath(_ path: String?) { set(path, for: SettingDefinitions.lastExportDirectoryPath) }

    /// 初回起動のチュートリアルを見せたかを読む。
    func loadHasShownFirstLaunchTutorial() -> Bool { value(SettingDefinitions.hasShownFirstLaunchTutorial) }

    /// 初回起動のチュートリアルを見せたかを保存する。
    func saveHasShownFirstLaunchTutorial(_ shown: Bool) {
        set(shown, for: SettingDefinitions.hasShownFirstLaunchTutorial)
    }

    /// サイドバーが開いているかを読む。
    func loadSidebarIsOpen() -> Bool { value(SettingDefinitions.isSidebarOpen) }

    /// サイドバーが開いているかを保存する。
    func saveSidebarIsOpen(_ isOpen: Bool) { set(isOpen, for: SettingDefinitions.isSidebarOpen) }

    /// サイドバーのタブを読む。
    func loadSidebarTab() -> SidebarTab { value(SettingDefinitions.sidebarTab) }

    /// サイドバーのタブを保存する。
    func saveSidebarTab(_ tab: SidebarTab) { set(tab, for: SettingDefinitions.sidebarTab) }

    /// 履歴に残す件数の上限を読む。
    func loadHistoryLimit() -> Int { value(SettingDefinitions.historyLimit) }

    /// 履歴に残す件数の上限を保存する。
    func saveHistoryLimit(_ limit: Int) { set(limit, for: SettingDefinitions.historyLimit) }

    /// 履歴を残す期間を読む。
    func loadHistoryRetention() -> HistoryRetention { value(SettingDefinitions.historyRetention) }

    /// 履歴を残す期間を保存する。
    func saveHistoryRetention(_ retention: HistoryRetention) {
        set(retention, for: SettingDefinitions.historyRetention)
    }

    /// パネルの既定の幅を読む。
    func loadPanelDefaultWidth() -> Double { value(SettingDefinitions.panelDefaultWidth) }

    /// パネルの既定の幅を保存する。
    func savePanelDefaultWidth(_ width: Double) { set(width, for: SettingDefinitions.panelDefaultWidth) }

    /// パネルの既定の高さを読む。
    func loadPanelDefaultHeight() -> Double { value(SettingDefinitions.panelDefaultHeight) }

    /// パネルの既定の高さを保存する。
    func savePanelDefaultHeight(_ height: Double) { set(height, for: SettingDefinitions.panelDefaultHeight) }
}
