import AppKit
import Observation

/// @note p0-157
@Observable final class AppSettings {
    var commitKey: PanelShortcut? {
        didSet { store.saveCommitShortcut(commitKey) }
    }

    var commitAndSendKey: PanelShortcut? {
        didSet { store.saveCommitAndSendShortcut(commitAndSendKey) }
    }

    var panelScreen: PanelScreen {
        didSet { store.savePanelScreen(panelScreen) }
    }

    var autoShowMode: AutoShowMode {
        didSet { store.saveAutoShowMode(autoShowMode) }
    }

    /// @note p0-158
    var autoShowApps: [AutoShowApp] {
        didSet {
            let normalized = AutoShowApp.normalized(autoShowApps)
            if normalized != autoShowApps {
                autoShowApps = normalized
            }
            store.saveAutoShowApps(autoShowApps)
        }
    }

    // @note p0-159

    /// @note p0-160
    var theme: AppTheme {
        didSet { store.saveAppTheme(theme) }
    }

    /// @note p0-161
    var panelFontName: String? {
        didSet {
            if panelFontName?.isEmpty == true {
                panelFontName = nil
            }
            store.savePanelFontName(panelFontName)
        }
    }

    /// 選んだフォントのファミリー名。`selectPanelFont(_:)` と `resetPanelFontToSystem()` で変える。
    private(set) var panelFontFamilyName: String? {
        didSet {
            if panelFontFamilyName?.isEmpty == true {
                panelFontFamilyName = nil
            }
            store.savePanelFontFamilyName(panelFontFamilyName)
        }
    }

    /// @note p0-162
    var panelFontSize: Double {
        didSet {
            let clamped = PanelTextStyle.clampedFontSize(panelFontSize)
            if clamped != panelFontSize {
                panelFontSize = clamped
            }
            store.savePanelFontSize(panelFontSize)
        }
    }

    /// @note p0-163
    var panelOpacity: Double {
        didSet {
            let clamped = PanelTextStyle.clampedOpacity(panelOpacity)
            if clamped != panelOpacity {
                panelOpacity = clamped
            }
            store.savePanelOpacity(panelOpacity)
        }
    }

    /// @note p0-164
    var hiddenPanelStatusItems: Set<PanelStatusItem> {
        didSet { store.saveHiddenPanelStatusItems(hiddenPanelStatusItems) }
    }

    /// @note p0-165
    var hidesMenuBarIcon: Bool {
        didSet { store.saveHidesMenuBarIcon(hidesMenuBarIcon) }
    }

    /// @note p0-166
    var isMenuBarIconShown: Bool {
        get { !hidesMenuBarIcon }
        set { hidesMenuBarIcon = !newValue }
    }

    /// @note p0-167
    var panelDefaultWidth: Double {
        didSet {
            let clamped = PanelMetrics.clampedDefaultWidth(panelDefaultWidth)
            if clamped != panelDefaultWidth {
                panelDefaultWidth = clamped
            }
            store.savePanelDefaultWidth(panelDefaultWidth)
        }
    }

    /// @note p0-168
    var panelDefaultHeight: Double {
        didSet {
            let clamped = PanelMetrics.clampedDefaultHeight(panelDefaultHeight)
            if clamped != panelDefaultHeight {
                panelDefaultHeight = clamped
            }
            store.savePanelDefaultHeight(panelDefaultHeight)
        }
    }

    @ObservationIgnored private let store: SettingsStore

    /// @note p0-169
    init(store: SettingsStore) {
        self.store = store
        self.commitKey = store.loadCommitShortcut()
        self.commitAndSendKey = store.loadCommitAndSendShortcut()
        self.panelScreen = store.loadPanelScreen()
        self.autoShowMode = store.loadAutoShowMode()
        // @note p0-170
        self.autoShowApps = store.loadAutoShowApps()
        // @note p0-171
        self.theme = store.loadAppTheme()
        let loadedFontName = store.loadPanelFontName()
        var loadedFamilyName = store.loadPanelFontFamilyName()
        if loadedFamilyName == nil, let loadedFontName, !PanelTextStyle.isSystemFontName(loadedFontName),
           let family = NSFont(name: loadedFontName, size: CGFloat(PanelTextStyle.defaultFontSize))?.familyName {
            loadedFamilyName = family
            store.savePanelFontFamilyName(family)
        }
        self.panelFontName = loadedFontName
        self.panelFontFamilyName = loadedFamilyName
        self.panelFontSize = store.loadPanelFontSize()
        self.panelOpacity = store.loadPanelOpacity()
        self.hiddenPanelStatusItems = store.loadHiddenPanelStatusItems()
        self.hidesMenuBarIcon = store.loadHidesMenuBarIcon()
        self.panelDefaultWidth = store.loadPanelDefaultWidth()
        self.panelDefaultHeight = store.loadPanelDefaultHeight()
    }

    /// @note p0-172
    var panelStatusItems: [PanelStatusItem] {
        PanelStatusItem.visibleItems(
            hidden: hiddenPanelStatusItems,
            commitKey: commitKey,
            commitAndSendKey: commitAndSendKey
        )
    }

    /// @note p0-173
    var panelFont: NSFont {
        PanelTextStyle.font(name: panelFontName, familyName: panelFontFamilyName, size: panelFontSize)
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

    /// @note p0-174
    var panelDefaultSize: CGSize {
        CGSize(width: panelDefaultWidth, height: panelDefaultHeight)
    }

    /// @note p0-175
    func setPanelStatusItem(_ item: PanelStatusItem, isVisible: Bool) {
        if isVisible {
            hiddenPanelStatusItems.remove(item)
        } else {
            hiddenPanelStatusItems.insert(item)
        }
    }

    // @note p0-176

    /// @note p0-177
    @discardableResult
    func selectCommitKey(_ key: PanelShortcut?) -> Bool {
        guard key == nil || key != commitAndSendKey else { return false }
        commitKey = key
        return true
    }

    /// @note p0-178
    @discardableResult
    func selectCommitAndSendKey(_ key: PanelShortcut?) -> Bool {
        guard key == nil || key != commitKey else { return false }
        commitAndSendKey = key
        return true
    }
}
