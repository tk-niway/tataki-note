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
        static let showsDockIcon = "showsDockIcon"
        static let confirmsQuit = "confirmsQuit"
        static let lastExportDirectory = "lastExportDirectory"
        static let checksForUpdatesAutomatically = "checksForUpdatesAutomatically"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let suppressesMoveToApplicationsPrompt = "suppressesMoveToApplicationsPrompt"
    }

    let defaults: any SettingsStorage

    // MARK: - 確定+挿入キー・確定+送信キー(新しい保存形式)

    func loadCommitShortcut() -> PanelShortcut? {
        loadShortcut(forKey: Key.commitShortcut, legacyKey: Key.commitKey, fallback: commitShortcutFallback())
    }

    func saveCommitShortcut(_ shortcut: PanelShortcut?) {
        saveShortcut(shortcut, forKey: Key.commitShortcut)
    }

    func loadCommitAndSendShortcut() -> PanelShortcut? {
        loadShortcut(
            forKey: Key.commitAndSendShortcut,
            legacyKey: Key.commitAndSendKey,
            fallback: commitAndSendShortcutFallback()
        )
    }

    func saveCommitAndSendShortcut(_ shortcut: PanelShortcut?) {
        saveShortcut(shortcut, forKey: Key.commitAndSendShortcut)
    }

    private func loadShortcut(forKey key: String, legacyKey: String, fallback: PanelShortcut?) -> PanelShortcut? {
        if let stored = defaults.object(forKey: key) {
            guard let array = stored as? [Any] else { return fallback }
            return array.isEmpty ? nil : (PanelShortcut(storedValue: array) ?? fallback)
        }
        if let legacy = defaults.string(forKey: legacyKey) {
            guard let actionKey = PanelActionKey(rawValue: legacy) else { return fallback }
            return actionKey.shortcut
        }
        return fallback
    }

    private func saveShortcut(_ shortcut: PanelShortcut?, forKey key: String) {
        defaults.set(shortcut?.storedValue ?? [], forKey: key)
    }

    private var hasLegacyActionKeys: Bool {
        defaults.object(forKey: Key.commitKey) != nil || defaults.object(forKey: Key.commitAndSendKey) != nil
    }

    private func commitShortcutFallback() -> PanelShortcut? {
        hasLegacyActionKeys ? PanelShortcut.legacyDefaultCommitKey : PanelShortcut.defaultCommitKey
    }

    private func commitAndSendShortcutFallback() -> PanelShortcut? {
        hasLegacyActionKeys ? PanelShortcut.legacyDefaultCommitAndSendKey : PanelShortcut.defaultCommitAndSendKey
    }

    // MARK: - モード

    func loadNewDraftMode() -> DraftMode {
        loadStringEnum(DraftMode.self, forKey: Key.newDraftMode) ?? .insert
    }

    func saveNewDraftMode(_ mode: DraftMode) {
        saveStringEnum(mode, forKey: Key.newDraftMode)
    }

    func loadPanelScreen() -> PanelScreen {
        loadStringEnum(PanelScreen.self, forKey: Key.panelScreen) ?? .defaultValue
    }

    func savePanelScreen(_ panelScreen: PanelScreen) {
        saveStringEnum(panelScreen, forKey: Key.panelScreen)
    }

    func loadAutoShowMode() -> AutoShowMode {
        loadStringEnum(AutoShowMode.self, forKey: Key.autoShowMode) ?? .defaultValue
    }

    func saveAutoShowMode(_ mode: AutoShowMode) {
        saveStringEnum(mode, forKey: Key.autoShowMode)
    }

    func loadAutoShowApps() -> [AutoShowApp] {
        guard let data = defaults.data(forKey: Key.autoShowApps) else { return [] }
        let apps = (try? JSONDecoder().decode([AutoShowApp].self, from: data)) ?? []
        return AutoShowApp.normalized(apps)
    }

    func saveAutoShowApps(_ apps: [AutoShowApp]) {
        guard let data = try? JSONEncoder().encode(AutoShowApp.normalized(apps)) else { return }
        defaults.set(data, forKey: Key.autoShowApps)
    }

    // MARK: - テーマ

    func loadAppTheme() -> AppTheme {
        loadStringEnum(AppTheme.self, forKey: Key.appTheme) ?? .defaultValue
    }

    func saveAppTheme(_ theme: AppTheme) {
        saveStringEnum(theme, forKey: Key.appTheme)
    }

    // MARK: - パネルの文字と透明度

    func loadPanelFontName() -> String? {
        loadNonEmptyString(forKey: Key.panelFontName)
    }

    func savePanelFontName(_ name: String?) {
        saveNonEmptyString(name, forKey: Key.panelFontName)
    }

    /// パネルの入力欄のフォントのファミリー名を読む。無い・空・文字列でない値は `nil`。
    func loadPanelFontFamilyName() -> String? {
        loadNonEmptyString(forKey: Key.panelFontFamilyName)
    }

    /// パネルの入力欄のフォントのファミリー名を保存する。`nil`・空文字ならキーを消す。
    func savePanelFontFamilyName(_ name: String?) {
        saveNonEmptyString(name, forKey: Key.panelFontFamilyName)
    }

    func loadPanelFontSize() -> Double {
        loadClampedNumber(
            forKey: Key.panelFontSize,
            defaultValue: PanelTextStyle.defaultFontSize,
            clamp: PanelTextStyle.clampedFontSize
        )
    }

    func savePanelFontSize(_ size: Double) {
        defaults.set(PanelTextStyle.clampedFontSize(size), forKey: Key.panelFontSize)
    }

    func loadPanelOpacity() -> Double {
        loadClampedNumber(
            forKey: Key.panelOpacity,
            defaultValue: PanelTextStyle.defaultOpacity,
            clamp: PanelTextStyle.clampedOpacity
        )
    }

    func savePanelOpacity(_ opacity: Double) {
        defaults.set(PanelTextStyle.clampedOpacity(opacity), forKey: Key.panelOpacity)
    }

    // MARK: - 帯の項目

    func loadHiddenPanelStatusItems() -> Set<PanelStatusItem> {
        guard let values = defaults.array(forKey: Key.hiddenPanelStatusItems) else { return [] }
        return Set(values.compactMap { ($0 as? String).flatMap(PanelStatusItem.init(rawValue:)) })
    }

    func saveHiddenPanelStatusItems(_ items: Set<PanelStatusItem>) {
        let rawValues = PanelStatusItem.allCases.filter { items.contains($0) }.map(\.rawValue)
        defaults.set(rawValues, forKey: Key.hiddenPanelStatusItems)
    }

    // MARK: - メニューバーのアイコン

    func loadHidesMenuBarIcon() -> Bool {
        boolean(forKey: Key.hidesMenuBarIcon) ?? false
    }

    func saveHidesMenuBarIcon(_ hides: Bool) {
        defaults.set(hides, forKey: Key.hidesMenuBarIcon)
    }

    // MARK: - アニメーション

    func loadAnimationMode() -> AnimationMode {
        loadStringEnum(AnimationMode.self, forKey: Key.animationMode) ?? .defaultValue
    }

    func saveAnimationMode(_ mode: AnimationMode) {
        saveStringEnum(mode, forKey: Key.animationMode)
    }

    // MARK: - 挿入先の枠線

    func loadIsInsertionTargetOutlineShown() -> Bool {
        boolean(forKey: Key.insertionTargetOutlineShown) ?? true
    }

    func saveIsInsertionTargetOutlineShown(_ isShown: Bool) {
        defaults.set(isShown, forKey: Key.insertionTargetOutlineShown)
    }

    // MARK: - Dock のアイコン

    func loadShowsDockIcon() -> Bool {
        boolean(forKey: Key.showsDockIcon) ?? true
    }

    func saveShowsDockIcon(_ shows: Bool) {
        defaults.set(shows, forKey: Key.showsDockIcon)
    }

    // MARK: - 終了の確かめ

    func loadConfirmsQuit() -> Bool {
        boolean(forKey: Key.confirmsQuit) ?? true
    }

    func saveConfirmsQuit(_ confirms: Bool) {
        defaults.set(confirms, forKey: Key.confirmsQuit)
    }

    // MARK: - アップデート

    func loadChecksForUpdatesAutomatically() -> Bool {
        boolean(forKey: Key.checksForUpdatesAutomatically) ?? true
    }

    func saveChecksForUpdatesAutomatically(_ checks: Bool) {
        defaults.set(checks, forKey: Key.checksForUpdatesAutomatically)
    }

    /// 前回アップデートを確かめた日時を読む。無い・数値でない・有限でない値は nil。
    func loadLastUpdateCheckDate() -> Date? {
        guard let seconds = number(forKey: Key.lastUpdateCheckDate)?.doubleValue, seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func saveLastUpdateCheckDate(_ date: Date?) {
        guard let date, date.timeIntervalSince1970.isFinite else {
            defaults.removeObject(forKey: Key.lastUpdateCheckDate)
            return
        }
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastUpdateCheckDate)
    }

    func loadSuppressesMoveToApplicationsPrompt() -> Bool {
        boolean(forKey: Key.suppressesMoveToApplicationsPrompt) ?? false
    }

    func saveSuppressesMoveToApplicationsPrompt(_ suppresses: Bool) {
        defaults.set(suppresses, forKey: Key.suppressesMoveToApplicationsPrompt)
    }

    // MARK: - 書き出し

    /// 前回書き出したフォルダのパスを読む。無い・文字列でない・空文字は nil。
    func loadLastExportDirectoryPath() -> String? {
        loadNonEmptyString(forKey: Key.lastExportDirectory)
    }

    func saveLastExportDirectoryPath(_ path: String?) {
        saveNonEmptyString(path, forKey: Key.lastExportDirectory)
    }

    // MARK: - 初回起動のチュートリアル

    func loadHasShownFirstLaunchTutorial() -> Bool {
        boolean(forKey: Key.hasShownFirstLaunchTutorial) ?? false
    }

    func saveHasShownFirstLaunchTutorial(_ shown: Bool) {
        defaults.set(shown, forKey: Key.hasShownFirstLaunchTutorial)
    }

    // MARK: - サイドバー

    func loadSidebarIsOpen() -> Bool {
        boolean(forKey: Key.sidebarIsOpen) ?? false
    }

    func saveSidebarIsOpen(_ isOpen: Bool) {
        defaults.set(isOpen, forKey: Key.sidebarIsOpen)
    }

    func loadSidebarTab() -> SidebarTab {
        loadStringEnum(SidebarTab.self, forKey: Key.sidebarTab) ?? .drafts
    }

    func saveSidebarTab(_ tab: SidebarTab) {
        saveStringEnum(tab, forKey: Key.sidebarTab)
    }

    // MARK: - 履歴の上限

    /// 履歴に残す件数の上限を読む。数値でない・無い・有限でない値は初期値、範囲外は端に丸める。
    func loadHistoryLimit() -> Int {
        guard let value = number(forKey: Key.historyLimit)?.doubleValue, value.isFinite else {
            return HistoryLimit.defaultValue
        }
        let lower = Double(HistoryLimit.range.lowerBound)
        let upper = Double(HistoryLimit.range.upperBound)
        return Int(min(max(value, lower), upper))
    }

    func saveHistoryLimit(_ limit: Int) {
        defaults.set(HistoryLimit.clamped(limit), forKey: Key.historyLimit)
    }

    // MARK: - パネルの既定の大きさ

    func loadPanelDefaultWidth() -> Double {
        loadPanelDefaultLength(
            forKey: Key.panelDefaultWidth,
            in: PanelMetrics.defaultWidthRange,
            defaultValue: Double(PanelMetrics.defaultSize.width)
        )
    }

    func savePanelDefaultWidth(_ width: Double) {
        defaults.set(PanelMetrics.clampedDefaultWidth(width), forKey: Key.panelDefaultWidth)
    }

    func loadPanelDefaultHeight() -> Double {
        loadPanelDefaultLength(
            forKey: Key.panelDefaultHeight,
            in: PanelMetrics.defaultHeightRange,
            defaultValue: Double(PanelMetrics.defaultSize.height)
        )
    }

    func savePanelDefaultHeight(_ height: Double) {
        defaults.set(PanelMetrics.clampedDefaultHeight(height), forKey: Key.panelDefaultHeight)
    }

    private func loadPanelDefaultLength(forKey key: String, in range: ClosedRange<Double>, defaultValue: Double) -> Double {
        guard let value = number(forKey: key)?.doubleValue, range.contains(value) else { return defaultValue }
        return value
    }

    // MARK: - 型で読み分ける

    private func loadStringEnum<T: RawRepresentable>(_ type: T.Type, forKey key: String) -> T? where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }

    private func saveStringEnum<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
    }

    private func loadNonEmptyString(forKey key: String) -> String? {
        guard let value = defaults.object(forKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    private func saveNonEmptyString(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadClampedNumber(forKey key: String, defaultValue: Double, clamp: (Double) -> Double) -> Double {
        guard let stored = number(forKey: key) else { return defaultValue }
        return clamp(stored.doubleValue)
    }

    private func number(forKey key: String) -> NSNumber? {
        guard let value = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID()
        else { return nil }
        return value
    }

    private func boolean(forKey key: String) -> Bool? {
        guard let value = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return value.boolValue
    }
}
