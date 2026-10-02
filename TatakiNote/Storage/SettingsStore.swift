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
    }

    let defaults: UserDefaults

    // MARK: - 確定キー・確定+送信キー(新しい保存形式)

    func loadCommitShortcut() -> PanelShortcut? {
        if let stored = defaults.object(forKey: Key.commitShortcut) {
            guard let array = stored as? [Any] else { return commitShortcutFallback() }
            return array.isEmpty ? nil : (PanelShortcut(storedValue: array) ?? commitShortcutFallback())
        }
        if let legacy = defaults.string(forKey: Key.commitKey) {
            guard let key = PanelActionKey(rawValue: legacy) else { return commitShortcutFallback() }
            return key.shortcut
        }
        return commitShortcutFallback()
    }

    func saveCommitShortcut(_ shortcut: PanelShortcut?) {
        defaults.set(shortcut?.storedValue ?? [], forKey: Key.commitShortcut)
    }

    func loadCommitAndSendShortcut() -> PanelShortcut? {
        if let stored = defaults.object(forKey: Key.commitAndSendShortcut) {
            guard let array = stored as? [Any] else { return commitAndSendShortcutFallback() }
            return array.isEmpty ? nil : (PanelShortcut(storedValue: array) ?? commitAndSendShortcutFallback())
        }
        if let legacy = defaults.string(forKey: Key.commitAndSendKey) {
            guard let key = PanelActionKey(rawValue: legacy) else { return commitAndSendShortcutFallback() }
            return key.shortcut
        }
        return commitAndSendShortcutFallback()
    }

    func saveCommitAndSendShortcut(_ shortcut: PanelShortcut?) {
        defaults.set(shortcut?.storedValue ?? [], forKey: Key.commitAndSendShortcut)
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

    func loadPanelScreen() -> PanelScreen {
        defaults.string(forKey: Key.panelScreen).flatMap(PanelScreen.init(rawValue:)) ?? .defaultValue
    }

    func savePanelScreen(_ panelScreen: PanelScreen) {
        defaults.set(panelScreen.rawValue, forKey: Key.panelScreen)
    }

    func loadAutoShowMode() -> AutoShowMode {
        defaults.string(forKey: Key.autoShowMode).flatMap(AutoShowMode.init(rawValue:)) ?? .defaultValue
    }

    func saveAutoShowMode(_ mode: AutoShowMode) {
        defaults.set(mode.rawValue, forKey: Key.autoShowMode)
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
        defaults.string(forKey: Key.appTheme).flatMap(AppTheme.init(rawValue:)) ?? .defaultValue
    }

    func saveAppTheme(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: Key.appTheme)
    }

    // MARK: - パネルの文字と透明度

    func loadPanelFontName() -> String? {
        guard let name = defaults.object(forKey: Key.panelFontName) as? String, !name.isEmpty else { return nil }
        return name
    }

    func savePanelFontName(_ name: String?) {
        if let name, !name.isEmpty {
            defaults.set(name, forKey: Key.panelFontName)
        } else {
            defaults.removeObject(forKey: Key.panelFontName)
        }
    }

    /// パネルの入力欄のフォントのファミリー名を読む。無い・空・文字列でない値は `nil`。
    func loadPanelFontFamilyName() -> String? {
        guard let name = defaults.object(forKey: Key.panelFontFamilyName) as? String, !name.isEmpty else { return nil }
        return name
    }

    /// パネルの入力欄のフォントのファミリー名を保存する。`nil`・空文字ならキーを消す。
    func savePanelFontFamilyName(_ name: String?) {
        if let name, !name.isEmpty {
            defaults.set(name, forKey: Key.panelFontFamilyName)
        } else {
            defaults.removeObject(forKey: Key.panelFontFamilyName)
        }
    }

    func loadPanelFontSize() -> Double {
        guard let stored = number(forKey: Key.panelFontSize) else { return PanelTextStyle.defaultFontSize }
        return PanelTextStyle.clampedFontSize(stored.doubleValue)
    }

    func savePanelFontSize(_ size: Double) {
        defaults.set(PanelTextStyle.clampedFontSize(size), forKey: Key.panelFontSize)
    }

    func loadPanelOpacity() -> Double {
        guard let stored = number(forKey: Key.panelOpacity) else { return PanelTextStyle.defaultOpacity }
        return PanelTextStyle.clampedOpacity(stored.doubleValue)
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
