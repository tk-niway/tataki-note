import AppKit
import Observation

/// 利用者が設定画面で変える値。
@Observable final class AppSettings {
    var commitKey: PanelShortcut? {
        didSet {
            store.saveCommitShortcut(commitKey)
            refreshKeyDisplayTexts()
        }
    }

    var commitAndSendKey: PanelShortcut? {
        didSet {
            store.saveCommitAndSendShortcut(commitAndSendKey)
            refreshKeyDisplayTexts()
        }
    }

    private(set) var commitKeyDisplayText: String?

    private(set) var commitAndSendKeyDisplayText: String?

    private(set) var panelFont: NSFont

    var panelScreen: PanelScreen {
        didSet { store.savePanelScreen(panelScreen) }
    }

    var autoShowMode: AutoShowMode {
        didSet { store.saveAutoShowMode(autoShowMode) }
    }

    var autoShowApps: [AutoShowApp] {
        didSet {
            let normalized = AutoShowApp.normalized(autoShowApps)
            if normalized != autoShowApps {
                autoShowApps = normalized
            }
            store.saveAutoShowApps(autoShowApps)
        }
    }


    var theme: AppTheme {
        didSet { store.saveAppTheme(theme) }
    }

    var panelFontName: String? {
        didSet {
            if panelFontName?.isEmpty == true {
                panelFontName = nil
            }
            store.savePanelFontName(panelFontName)
            refreshPanelFont()
        }
    }

    /// 選んだフォントのファミリー名。`selectPanelFont(_:)` と `resetPanelFontToSystem()` で変える。
    private(set) var panelFontFamilyName: String? {
        didSet {
            if panelFontFamilyName?.isEmpty == true {
                panelFontFamilyName = nil
            }
            store.savePanelFontFamilyName(panelFontFamilyName)
            refreshPanelFont()
        }
    }

    var panelFontSize: Double {
        didSet {
            let clamped = PanelTextStyle.clampedFontSize(panelFontSize)
            if clamped != panelFontSize {
                panelFontSize = clamped
            }
            store.savePanelFontSize(panelFontSize)
            refreshPanelFont()
        }
    }

    var panelOpacity: Double {
        didSet {
            let clamped = PanelTextStyle.clampedOpacity(panelOpacity)
            if clamped != panelOpacity {
                panelOpacity = clamped
            }
            store.savePanelOpacity(panelOpacity)
        }
    }

    var hiddenPanelStatusItems: Set<PanelStatusItem> {
        didSet { store.saveHiddenPanelStatusItems(hiddenPanelStatusItems) }
    }

    var hidesMenuBarIcon: Bool {
        didSet { store.saveHidesMenuBarIcon(hidesMenuBarIcon) }
    }

    var isMenuBarIconShown: Bool {
        get { !hidesMenuBarIcon }
        set { hidesMenuBarIcon = !newValue }
    }

    var panelDefaultWidth: Double {
        didSet {
            let clamped = PanelMetrics.clampedDefaultWidth(panelDefaultWidth)
            if clamped != panelDefaultWidth {
                panelDefaultWidth = clamped
            }
            store.savePanelDefaultWidth(panelDefaultWidth)
        }
    }

    var panelDefaultHeight: Double {
        didSet {
            let clamped = PanelMetrics.clampedDefaultHeight(panelDefaultHeight)
            if clamped != panelDefaultHeight {
                panelDefaultHeight = clamped
            }
            store.savePanelDefaultHeight(panelDefaultHeight)
        }
    }

    /// パネルの開閉エフェクトを使うか。
    var isPanelAnimationEnabled: Bool {
        didSet { store.saveIsPanelAnimationEnabled(isPanelAnimationEnabled) }
    }

    /// 挿入先の入力欄を枠線で囲むか。
    var isInsertionTargetOutlineShown: Bool {
        didSet { store.saveIsInsertionTargetOutlineShown(isInsertionTargetOutlineShown) }
    }

    /// 初回起動のチュートリアルを自動で出したか。
    var hasShownFirstLaunchTutorial: Bool {
        didSet { store.saveHasShownFirstLaunchTutorial(hasShownFirstLaunchTutorial) }
    }

    /// サイドバーを開いているか。
    var isSidebarOpen: Bool {
        didSet { store.saveSidebarIsOpen(isSidebarOpen) }
    }

    /// サイドバーで表示している側。
    var sidebarTab: SidebarTab {
        didSet { store.saveSidebarTab(sidebarTab) }
    }

    /// 履歴に残す件数の上限。
    var historyLimit: Int {
        didSet {
            let clamped = HistoryLimit.clamped(historyLimit)
            if clamped != historyLimit {
                historyLimit = clamped
            }
            store.saveHistoryLimit(historyLimit)
        }
    }

    /// 今のモード。`selectAppMode(_:hotkey:)` で変える。
    private(set) var appMode: AppMode {
        didSet { store.saveAppMode(appMode) }
    }

    /// 新しい書きかけを始めるモード。
    var newDraftMode: DraftMode {
        didSet { store.saveNewDraftMode(newDraftMode) }
    }

    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        self.appMode = store.loadAppMode()
        self.newDraftMode = store.loadNewDraftMode()
        self.commitKey = store.loadCommitShortcut()
        self.commitAndSendKey = store.loadCommitAndSendShortcut()
        self.panelScreen = store.loadPanelScreen()
        self.autoShowMode = store.loadAutoShowMode()
        self.autoShowApps = store.loadAutoShowApps()
        self.theme = store.loadAppTheme()
        let loadedFontName = store.loadPanelFontName()
        var loadedFamilyName = store.loadPanelFontFamilyName()
        if loadedFamilyName == nil, let loadedFontName, !PanelTextStyle.isSystemFontName(loadedFontName),
           let family = NSFont(name: loadedFontName, size: CGFloat(PanelTextStyle.defaultFontSize))?.familyName {
            loadedFamilyName = family
            store.savePanelFontFamilyName(family)
        }
        let loadedFontSize = store.loadPanelFontSize()
        self.panelFontName = loadedFontName
        self.panelFontFamilyName = loadedFamilyName
        self.panelFontSize = loadedFontSize
        self.panelFont = PanelTextStyle.font(name: loadedFontName, familyName: loadedFamilyName, size: loadedFontSize)
        self.panelOpacity = store.loadPanelOpacity()
        self.hiddenPanelStatusItems = store.loadHiddenPanelStatusItems()
        self.hidesMenuBarIcon = store.loadHidesMenuBarIcon()
        self.panelDefaultWidth = store.loadPanelDefaultWidth()
        self.panelDefaultHeight = store.loadPanelDefaultHeight()
        self.isPanelAnimationEnabled = store.loadIsPanelAnimationEnabled()
        self.isInsertionTargetOutlineShown = store.loadIsInsertionTargetOutlineShown()
        self.hasShownFirstLaunchTutorial = store.loadHasShownFirstLaunchTutorial()
        self.isSidebarOpen = store.loadSidebarIsOpen()
        self.sidebarTab = store.loadSidebarTab()
        self.historyLimit = store.loadHistoryLimit()
        self.commitKeyDisplayText = commitKey?.displayText
        self.commitAndSendKeyDisplayText = commitAndSendKey?.displayText
    }

    var isNoteMode: Bool {
        appMode == .note
    }

    /// モードを切り替える。インサートモードにしたとき確定キーが両方とも未登録なら、初期値を登録する(ホットキーと同じキーは除く)。
    func selectAppMode(_ mode: AppMode, hotkey: PanelShortcut?) {
        guard mode != appMode else { return }
        if mode == .insert {
            registerDefaultCommitKeysIfBothMissing(hotkey: hotkey)
        }
        appMode = mode
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

    /// 実際に使う「パネルを出す位置」。ノートモードでは「入力欄の近く」を「マウスの近く」にする。
    var effectivePanelScreen: PanelScreen {
        isNoteMode && panelScreen == .nearFocusedField ? .mouse : panelScreen
    }

    /// 実際に使う自動表示の設定。ノートモードではオフ。
    var effectiveAutoShowMode: AutoShowMode {
        isNoteMode ? .off : autoShowMode
    }

    /// 挿入先の枠線を実際に出すか。ノートモードでは出さない。
    var isInsertionTargetOutlineActive: Bool {
        !isNoteMode && isInsertionTargetOutlineShown
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
