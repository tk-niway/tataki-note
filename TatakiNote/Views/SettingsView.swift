import SwiftUI

/// 設定画面。
struct SettingsView: View {
    static let windowSize = CGSize(width: 720, height: 600)
    static let sidebarWidth: CGFloat = 212
    static let dividerWidth: CGFloat = 1
    static let sidebarEdgeInset: CGFloat = 12

    /// 右側の中身の幅。ウィンドウの幅からサイドバーと区切り線を引いた残り。
    static var detailWidth: CGFloat { windowSize.width - sidebarWidth - dividerWidth }

    @Bindable var settings: AppSettings
    @Bindable var model: SettingsWindowModel
    let launchAtLogin: LaunchAtLoginModel
    let appInfo: AppInfoModel
    let panelDefaultSize: PanelDefaultSizeModel
    let onShowFontPanel: () -> Void
    let onQuit: () -> Void

    @State private var editorModel: EditorSettingsModel
    @State private var keySettingsModel: PanelKeySettingsModel
    @State private var historyModel: HistorySettingsModel

    init(
        settings: AppSettings,
        model: SettingsWindowModel,
        launchAtLogin: LaunchAtLoginModel,
        appInfo: AppInfoModel,
        panelDefaultSize: PanelDefaultSizeModel,
        library: DraftLibrary = DraftLibrary(store: .inMemory),
        onShowFontPanel: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settings = settings
        self.model = model
        self.launchAtLogin = launchAtLogin
        self.appInfo = appInfo
        self.panelDefaultSize = panelDefaultSize
        self.onShowFontPanel = onShowFontPanel
        self.onQuit = onQuit
        _editorModel = State(initialValue: EditorSettingsModel(settings: settings))
        _keySettingsModel = State(initialValue: PanelKeySettingsModel(settings: settings))
        _historyModel = State(initialValue: HistorySettingsModel(library: library))
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(settings: settings, model: model, onQuit: onQuit)
            Divider()
            VStack(spacing: 0) {
                Text(model.selectedSection.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, SettingsDetailLayout.headerTop)
                    .padding(.horizontal, SettingsDetailLayout.leading)
                    .padding(.bottom, SettingsDetailLayout.headerBottom)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.detailTitle")
                ZStack {
                    ScrollView(.vertical) {
                        detail
                            .frame(width: Self.detailWidth, alignment: .leading)
                    }
                    .id(model.selectedSection)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .identity
                    ))
                    .accessibilityIdentifier("settings.detailScrollView")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(width: Self.detailWidth, height: Self.windowSize.height)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .leading)
        .ignoresSafeArea(edges: .top)
        .windowStyle(theme: settings.theme)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .general:
            GeneralSettingsView(settings: settings, launchAtLogin: launchAtLogin, history: historyModel)
        case .keys:
            KeySettingsView(keySettings: keySettingsModel, isNoteMode: settings.isNoteMode)
        case .panel:
            PanelSettingsView(
                settings: settings,
                model: editorModel,
                panelDefaultSize: panelDefaultSize,
                onShowFontPanel: onShowFontPanel
            )
        case .appInfo:
            AppInfoSettingsView(model: appInfo)
        }
    }

}
