import AppKit
import Observation

/// 利用者が設定画面で変える値。
@Observable final class AppSettings {
    var commitKey: PanelShortcut? {
        didSet {
            store.persist(\.commitKey, of: self, as: SettingDefinitions.commitKey)
            refreshKeyDisplayTexts()
        }
    }

    var commitAndSendKey: PanelShortcut? {
        didSet {
            store.persist(\.commitAndSendKey, of: self, as: SettingDefinitions.commitAndSendKey)
            refreshKeyDisplayTexts()
        }
    }

    private(set) var commitKeyDisplayText: String?

    private(set) var commitAndSendKeyDisplayText: String?

    private(set) var panelFont: NSFont

    var panelScreen: PanelScreen {
        didSet { store.persist(\.panelScreen, of: self, as: SettingDefinitions.panelScreen) }
    }

    var autoShowMode: AutoShowMode {
        didSet { store.persist(\.autoShowMode, of: self, as: SettingDefinitions.autoShowMode) }
    }

    var autoShowApps: [AutoShowApp] {
        didSet { store.persist(\.autoShowApps, of: self, as: SettingDefinitions.autoShowApps) }
    }

    var theme: AppTheme {
        didSet { store.persist(\.theme, of: self, as: SettingDefinitions.theme) }
    }

    var panelFontName: String? {
        didSet {
            store.persist(\.panelFontName, of: self, as: SettingDefinitions.panelFontName)
            refreshPanelFont()
        }
    }

    /// 選んだフォントのファミリー名。`selectPanelFont(_:)` と `resetPanelFontToSystem()` で変える。
    private(set) var panelFontFamilyName: String? {
        didSet {
            store.persist(\.panelFontFamilyName, of: self, as: SettingDefinitions.panelFontFamilyName)
            refreshPanelFont()
        }
    }

    var panelFontSize: Double {
        didSet {
            store.persist(\.panelFontSize, of: self, as: SettingDefinitions.panelFontSize)
            refreshPanelFont()
        }
    }

    var panelOpacity: Double {
        didSet { store.persist(\.panelOpacity, of: self, as: SettingDefinitions.panelOpacity) }
    }

    var hiddenPanelStatusItems: Set<PanelStatusItem> {
        didSet { store.persist(\.hiddenPanelStatusItems, of: self, as: SettingDefinitions.hiddenPanelStatusItems) }
    }

    /// メニューバーにアイコンを表示するか。
    var isMenuBarIconShown: Bool {
        didSet { store.persist(\.isMenuBarIconShown, of: self, as: SettingDefinitions.isMenuBarIconShown) }
    }

    var panelDefaultWidth: Double {
        didSet { store.persist(\.panelDefaultWidth, of: self, as: SettingDefinitions.panelDefaultWidth) }
    }

    var panelDefaultHeight: Double {
        didSet { store.persist(\.panelDefaultHeight, of: self, as: SettingDefinitions.panelDefaultHeight) }
    }

    /// 「アニメーション」の選択。
    var animationMode: AnimationMode {
        didSet { store.persist(\.animationMode, of: self, as: SettingDefinitions.animationMode) }
    }

    /// 今、動きを使うか。
    var isAnimationEnabled: Bool {
        animationMode.isEnabled(reduceMotion: reducesMotion())
    }

    /// 挿入先の入力欄を枠線で囲むか。
    var isInsertionTargetOutlineShown: Bool {
        didSet {
            store.persist(
                \.isInsertionTargetOutlineShown,
                of: self,
                as: SettingDefinitions.isInsertionTargetOutlineShown
            )
        }
    }

    /// Dock にアイコンを表示するか。
    var showsDockIcon: Bool {
        didSet { store.persist(\.showsDockIcon, of: self, as: SettingDefinitions.showsDockIcon) }
    }

    /// ⌘Q で終了前に確認するか。
    var confirmsQuit: Bool {
        didSet { store.persist(\.confirmsQuit, of: self, as: SettingDefinitions.confirmsQuit) }
    }

    /// 履歴に残す件数の上限。
    var historyLimit: Int {
        didSet { store.persist(\.historyLimit, of: self, as: SettingDefinitions.historyLimit) }
    }

    /// 履歴を残す期間。
    var historyRetention: HistoryRetention {
        didSet { store.persist(\.historyRetention, of: self, as: SettingDefinitions.historyRetention) }
    }

    /// 新しい書きかけを始めるモード。
    var newDraftMode: DraftMode {
        didSet { store.persist(\.newDraftMode, of: self, as: SettingDefinitions.newDraftMode) }
    }

    /// 1日に1回、新しい版を自動で確かめるか。
    var checksForUpdatesAutomatically: Bool {
        didSet {
            store.persist(
                \.checksForUpdatesAutomatically,
                of: self,
                as: SettingDefinitions.checksForUpdatesAutomatically
            )
        }
    }

    /// アプリが自分で覚えておく状態。
    let state: AppState

    @ObservationIgnored private let store: SettingsStore

    @ObservationIgnored private let reducesMotion: () -> Bool

    init(
        store: SettingsStore,
        reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.store = store
        self.reducesMotion = reducesMotion
        self.state = AppState(store: store)
        self.newDraftMode = store.value(SettingDefinitions.newDraftMode)
        self.commitKey = store.value(SettingDefinitions.commitKey)
        self.commitAndSendKey = store.value(SettingDefinitions.commitAndSendKey)
        self.panelScreen = store.value(SettingDefinitions.panelScreen)
        self.autoShowMode = store.value(SettingDefinitions.autoShowMode)
        self.autoShowApps = store.value(SettingDefinitions.autoShowApps)
        self.theme = store.value(SettingDefinitions.theme)
        let loadedFontName = store.value(SettingDefinitions.panelFontName)
        var loadedFamilyName = store.value(SettingDefinitions.panelFontFamilyName)
        if loadedFamilyName == nil, let loadedFontName, !PanelTextStyle.isSystemFontName(loadedFontName),
           let family = NSFont(name: loadedFontName, size: CGFloat(PanelTextStyle.defaultFontSize))?.familyName {
            loadedFamilyName = family
            store.set(family, for: SettingDefinitions.panelFontFamilyName)
        }
        let loadedFontSize = store.value(SettingDefinitions.panelFontSize)
        self.panelFontName = loadedFontName
        self.panelFontFamilyName = loadedFamilyName
        self.panelFontSize = loadedFontSize
        self.panelFont = PanelTextStyle.font(name: loadedFontName, familyName: loadedFamilyName, size: loadedFontSize)
        self.panelOpacity = store.value(SettingDefinitions.panelOpacity)
        self.hiddenPanelStatusItems = store.value(SettingDefinitions.hiddenPanelStatusItems)
        self.isMenuBarIconShown = store.value(SettingDefinitions.isMenuBarIconShown)
        self.panelDefaultWidth = store.value(SettingDefinitions.panelDefaultWidth)
        self.panelDefaultHeight = store.value(SettingDefinitions.panelDefaultHeight)
        self.animationMode = store.value(SettingDefinitions.animationMode)
        self.isInsertionTargetOutlineShown = store.value(SettingDefinitions.isInsertionTargetOutlineShown)
        self.showsDockIcon = store.value(SettingDefinitions.showsDockIcon)
        self.confirmsQuit = store.value(SettingDefinitions.confirmsQuit)
        self.historyLimit = store.value(SettingDefinitions.historyLimit)
        self.historyRetention = store.value(SettingDefinitions.historyRetention)
        self.checksForUpdatesAutomatically = store.value(SettingDefinitions.checksForUpdatesAutomatically)
        self.commitKeyDisplayText = commitKey?.displayText
        self.commitAndSendKeyDisplayText = commitAndSendKey?.displayText
    }

    /// 確定+挿入キーと確定+送信キーが両方とも未登録なら、初期値を登録する(ホットキーと同じキーは除く)。
    func registerDefaultCommitKeysIfBothMissing(hotkey: PanelShortcut?) {
        guard commitKey == nil, commitAndSendKey == nil else { return }
        if let key = PanelShortcut.defaultCommitKey, key != hotkey {
            commitKey = key
        }
        if let key = PanelShortcut.defaultCommitAndSendKey, key != hotkey {
            commitAndSendKey = key
        }
    }

    /// 帯に出す項目。ノートの書きかけでは確定+挿入・確定+送信を出さない。
    func panelStatusItems(for mode: DraftMode) -> [PanelStatusItem] {
        PanelStatusItem.visibleItems(
            hidden: hiddenPanelStatusItems,
            commitKey: mode == .note ? nil : commitKey,
            commitAndSendKey: mode == .note ? nil : commitAndSendKey
        )
    }

    /// 帯に出す確定キー・確定+送信キーの表示文字を、今のキーから作り直す。変わったときだけ入れ替える。
    func refreshKeyDisplayTexts() {
        let commitText = commitKey?.displayText
        if commitText != commitKeyDisplayText {
            commitKeyDisplayText = commitText
        }
        let commitAndSendText = commitAndSendKey?.displayText
        if commitAndSendText != commitAndSendKeyDisplayText {
            commitAndSendKeyDisplayText = commitAndSendText
        }
    }

    private func refreshPanelFont() {
        panelFont = PanelTextStyle.font(name: panelFontName, familyName: panelFontFamilyName, size: panelFontSize)
    }

    /// システムフォントではなく、Mac にある書体を使っているときのその書体。
    var resolvedPanelFont: NSFont? {
        PanelTextStyle.resolvedFont(name: panelFontName, familyName: panelFontFamilyName, size: panelFontSize)
    }

    /// フォントパネルで選んだ書体と大きさを設定に入れる。
    func selectPanelFont(_ font: NSFont) {
        if PanelTextStyle.isSystemFontName(font.fontName) {
            panelFontName = nil
            panelFontFamilyName = nil
        } else {
            panelFontName = font.fontName
            panelFontFamilyName = font.familyName
        }
        panelFontSize = Double(font.pointSize).rounded()
    }

    /// フォントをシステムフォントに戻す。文字サイズは変えない。
    func resetPanelFontToSystem() {
        panelFontName = nil
        panelFontFamilyName = nil
    }

    var panelDefaultSize: CGSize {
        CGSize(width: panelDefaultWidth, height: panelDefaultHeight)
    }

    func setPanelStatusItem(_ item: PanelStatusItem, isVisible: Bool) {
        if isVisible {
            hiddenPanelStatusItems.remove(item)
        } else {
            hiddenPanelStatusItems.insert(item)
        }
    }


    @discardableResult
    func selectCommitKey(_ key: PanelShortcut?) -> Bool {
        guard key == nil || key != commitAndSendKey else { return false }
        commitKey = key
        return true
    }

    @discardableResult
    func selectCommitAndSendKey(_ key: PanelShortcut?) -> Bool {
        guard key == nil || key != commitKey else { return false }
        commitAndSendKey = key
        return true
    }
}
