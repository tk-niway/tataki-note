import SwiftUI

/// @note p0-697
struct SettingsView: View {
    /// @note p0-698
    static let windowSize = CGSize(width: 660, height: 680)
    /// @note p0-699
    static let sidebarWidth: CGFloat = 180

    @Bindable var settings: AppSettings
    @Bindable var model: SettingsWindowModel
    let launchAtLogin: LaunchAtLoginModel
    let appInfo: AppInfoModel
    /// @note p0-700
    let panelDefaultSize: PanelDefaultSizeModel
    let onQuit: () -> Void

    /// @note p0-701
    @State private var editorModel: EditorSettingsModel
    /// @note p0-702
    @State private var keySettingsModel: PanelKeySettingsModel

    // @note p0-703
    init(
        settings: AppSettings,
        model: SettingsWindowModel,
        launchAtLogin: LaunchAtLoginModel,
        appInfo: AppInfoModel,
        panelDefaultSize: PanelDefaultSizeModel,
        onQuit: @escaping () -> Void
    ) {
        self.settings = settings
        self.model = model
        self.launchAtLogin = launchAtLogin
        self.appInfo = appInfo
        self.panelDefaultSize = panelDefaultSize
        self.onQuit = onQuit
        _editorModel = State(initialValue: EditorSettingsModel(settings: settings))
        _keySettingsModel = State(initialValue: PanelKeySettingsModel(settings: settings))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            Divider()
            // @note p0-704
            ScrollView(.vertical) {
                // @note p0-705
                switch model.selectedSection {
                case .general:
                    GeneralSettingsView(settings: settings, keySettings: keySettingsModel, launchAtLogin: launchAtLogin)
                case .editor:
                    EditorSettingsView(settings: settings, model: editorModel, panelDefaultSize: panelDefaultSize)
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
        // @note p0-706
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

    /// @note p0-707
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
