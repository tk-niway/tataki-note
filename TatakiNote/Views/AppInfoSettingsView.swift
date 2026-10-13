import SwiftUI

/// 設定画面の「情報」。
struct AppInfoSettingsView: View {
    let model: AppInfoModel

    var body: some View {
        VStack(spacing: 18) {
            header
            SettingsCard {
                permissionRow
                tutorialRow
            }
            Text("アイコンを叩いてみてください")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .settingsDetailPadding()
        .task {
            await model.watchPermission()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            AppIconTapButton()
                .padding(.top, 8)
                .padding(.bottom, 6)
            Text("TatakiNote")
                .font(.system(size: 20, weight: .bold))
            Text("バージョン \(model.versionText)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.appInfo.version")
            SettingDescription(text: "かっこの中はビルド番号です。")
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionRow: some View {
        VStack(spacing: 0) {
            SettingsRow(
                title: "アクセシビリティの許可",
                description: SettingsHelpText.accessibilityPermission
            ) {
                PermissionBadge(isGranted: model.permissionStatus.isTrusted, text: model.permissionBadgeText)
            }
            if !model.permissionStatus.isTrusted {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionGuideSteps(identifier: "settings.appInfo.permissionSteps")
                    Button("システム設定を開く") {
                        model.permissionStatus.openSystemSettings()
                    }
                    .accessibilityIdentifier("settings.appInfo.openSystemSettings")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var tutorialRow: some View {
        SettingsRow(
            title: "チュートリアル",
            description: AppInfoModel.tutorialDescription
        ) {
            Button("チュートリアルを開く") {
                model.openTutorial()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("settings.appInfo.openTutorial")
        }
    }
}

private struct PermissionBadge: View {
    let isGranted: Bool
    let text: String

    private var tint: Color {
        isGranted ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isGranted ? "checkmark" : "exclamationmark")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.15)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("settings.appInfo.permissionStatus")
    }
}
