import SwiftUI

/// 設定ウィンドウの左側(モードのカード・種類の一覧・終了ボタン)。
struct SettingsSidebar: View {
    static let trafficLightsInset: CGFloat = 28

    @Bindable var settings: AppSettings
    @Bindable var model: SettingsWindowModel
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeCard
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarRow(
                        section: section,
                        isSelected: model.selectedSection == section,
                        action: { select(section) }
                    )
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

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("モード")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            AppModeSwitch(selection: settings.appMode) { mode in
                model.selectAppMode(mode, in: settings)
            }
            SettingDescription(appModeDescription)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .keyframeAnimator(initialValue: 1.0, trigger: settings.appMode) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(reduceMotion ? 1.0 : 0.97, duration: 0.12)
                LinearKeyframe(reduceMotion ? 1.0 : 1.01, duration: 0.14)
                LinearKeyframe(1.0, duration: 0.12)
            }
        }
    }

    private var appModeDescription: String {
        switch settings.appMode {
        case .insert: String(localized: "書いた文章を、元のアプリの入力欄に挿入します。")
        case .note: String(localized: "挿入せず、パネルで書くだけで使います。")
        }
    }

    private func select(_ section: SettingsSection) {
        guard section != model.selectedSection else { return }
        if reduceMotion {
            model.selectedSection = section
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                model.selectedSection = section
            }
        }
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
