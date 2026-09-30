import SwiftUI

/// @note p0-590
struct AppInfoSettingsView: View {
    let model: AppInfoModel

    var body: some View {
        Form {
            LabeledContent("バージョン") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: model.versionText)
                        .accessibilityIdentifier("settings.appInfo.version")
                    SettingDescription(text: "かっこの中はビルド番号です。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("権限") {
                HStack(alignment: .top, spacing: 16) {
                    if model.permissionStatus.isTrusted {
                        PermissionGuideIcon(isGranted: true)
                        PermissionGuideStatus(isGranted: true, identifier: "settings.appInfo.permissionStatus")
                    } else {
                        PermissionGuideIcon(isGranted: false)
                        VStack(alignment: .leading, spacing: 14) {
                            PermissionGuideStatus(isGranted: false, identifier: "settings.appInfo.permissionStatus")
                            PermissionGuideSteps(identifier: "settings.appInfo.permissionSteps")
                            // @note p0-591
                            Button("システム設定を開く") {
                                model.permissionStatus.openSystemSettings()
                            }
                            .accessibilityIdentifier("settings.appInfo.openSystemSettings")
                        }
                    }
                }
            }
        }
        .formStyle(.columns)
        .settingsDetailPadding()
        // @note p0-592
        .task {
            await model.watchPermission()
        }
    }
}
