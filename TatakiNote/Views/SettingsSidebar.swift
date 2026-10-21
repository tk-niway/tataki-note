import SwiftUI

/// 設定ウィンドウの左側(種類の一覧・終了ボタン)。
struct SettingsSidebar: View {
    static let trafficLightsInset: CGFloat = 28

    @Bindable var model: SettingsWindowModel
    var badgedSections: Set<SettingsSection> = []
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    ZStack(alignment: .trailing) {
                        SettingsSidebarRow(
                            section: section,
                            isSelected: model.selectedSection == section,
                            action: { select(section) }
                        )
                        if badgedSections.contains(section) {
                            Circle()
                                .fill(Color(nsColor: .systemRed))
                                .frame(width: 8, height: 8)
                                .padding(.trailing, 10)
                                .allowsHitTesting(false)
                                .accessibilityElement()
                                .accessibilityLabel("新しい版があります")
                                .accessibilityIdentifier("settings.sidebar.updateBadge")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button("TatakiNote を終了", action: onQuit)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("settings.quit")
        }
        .padding(.horizontal, SettingsView.sidebarEdgeInset)
        .padding(.top, Self.trafficLightsInset)
        .padding(.bottom, SettingsView.sidebarEdgeInset)
        .frame(width: SettingsView.sidebarWidth, height: SettingsView.windowSize.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(0.03)))
    }

    private func select(_ section: SettingsSection) {
        guard section != model.selectedSection else { return }
        model.selectedSection = section
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.18))
                    )
                    .accessibilityHidden(true)
                Text(section.displayName)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.17) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.displayName)
        .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
