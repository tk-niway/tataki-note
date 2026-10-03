import SwiftUI

/// 設定画面。
struct SettingsView: View {
    static let windowSize = CGSize(width: 660, height: 680)
    static let sidebarWidth: CGFloat = 180

    @Bindable var settings: AppSettings
    @Bindable var model: SettingsWindowModel
    let launchAtLogin: LaunchAtLoginModel
    let appInfo: AppInfoModel
    let panelDefaultSize: PanelDefaultSizeModel
    let onShowFontPanel: () -> Void
    let onQuit: () -> Void

    @State private var editorModel: EditorSettingsModel
    @State private var keySettingsModel: PanelKeySettingsModel

    init(
        settings: AppSettings,
        model: SettingsWindowModel,
        launchAtLogin: LaunchAtLoginModel,
        appInfo: AppInfoModel,
        panelDefaultSize: PanelDefaultSizeModel,
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
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            Divider()
            ScrollView(.vertical) {
                switch model.selectedSection {
                case .general:
                    GeneralSettingsView(settings: settings, launchAtLogin: launchAtLogin)
                case .keys:
                    KeySettingsView(keySettings: keySettingsModel)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("settings.detailScrollView")
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .windowStyle(theme: settings.theme)
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: selectedSectionBinding) { section in
            Label(section.displayName, systemImage: section.systemImage)
                .tag(section)
                .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(action: onQuit) {
                Label("TatakiNote を終了", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("settings.quit")
            .padding(12)
        }
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
