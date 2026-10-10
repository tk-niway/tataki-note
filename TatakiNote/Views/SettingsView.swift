import SwiftUI

/// 設定画面。
struct SettingsView: View {
    static let windowSize = CGSize(width: 660, height: 680)
    static let sidebarWidth: CGFloat = 180
    static let dividerWidth: CGFloat = 1
    static let sidebarEdgeInset: CGFloat = 20

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
            sidebar
                .frame(width: Self.sidebarWidth, height: Self.windowSize.height)
            Divider()
            ScrollView(.vertical) {
                detail
                    .frame(width: Self.detailWidth, alignment: .leading)
            }
            .frame(width: Self.detailWidth, height: Self.windowSize.height)
            .clipped()
            .accessibilityIdentifier("settings.detailScrollView")
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .leading)
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

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: selectedSectionBinding) { section in
            Label(section.displayName, systemImage: section.systemImage)
                .tag(section)
                .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
                .listRowInsets(EdgeInsets(top: 0, leading: Self.sidebarEdgeInset - 8, bottom: 0, trailing: 8))
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            appModeToggle
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onQuit) {
                Label("TatakiNote を終了", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("settings.quit")
            .padding(.horizontal, Self.sidebarEdgeInset)
            .padding(.vertical, 12)
        }
    }

    private var appModeToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("モード")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Picker("モード", selection: appModeBinding) {
                    Text("インサート")
                        .tag(AppMode.insert)
                        .accessibilityLabel(AppMode.insert.displayName)
                        .accessibilityIdentifier("settings.appMode.insert")
                    Text("ノート")
                        .tag(AppMode.note)
                        .accessibilityLabel(AppMode.note.displayName)
                        .accessibilityIdentifier("settings.appMode.note")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityIdentifier("settings.appModeToggle")
                SettingDescription(appModeDescription)
            }
            .padding(.horizontal, Self.sidebarEdgeInset)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
        }
    }

    private var appModeDescription: String {
        switch settings.appMode {
        case .insert: String(localized: "書いた文章を、元のアプリの入力欄に挿入します。")
        case .note: String(localized: "挿入せず、パネルで書くだけで使います。")
        }
    }

    private var appModeBinding: Binding<AppMode> {
        Binding(
            get: { settings.appMode },
            set: { settings.selectAppMode($0, hotkey: PanelShortcut.currentHotkey()) }
        )
    }

    private var selectedSectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { model.selectedSection },
            set: { section in
                guard let section else { return }
                model.selectedSection = section
            }
        )
    }
}
