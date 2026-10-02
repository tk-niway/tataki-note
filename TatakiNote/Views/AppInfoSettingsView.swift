import SwiftUI

/// 設定画面の「アプリ情報」。
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
                            Button("システム設定を開く") {
                                model.permissionStatus.openSystemSettings()
                            }
                            .accessibilityIdentifier("settings.appInfo.openSystemSettings")
                        }
                    }
                }
            }
            .padding(.bottom, 12)

            LabeledContent("チュートリアル") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("チュートリアルを開く") {
                        model.openTutorial()
                    }
                    .accessibilityIdentifier("settings.appInfo.openTutorial")
                    SettingDescription(text: "練習用の入力欄で、パネルを開いて書いて挿入するまでをたどります。")
                }
            }
        }
        .formStyle(.columns)
        .settingsDetailPadding()
        .task {
            await model.watchPermission()
        }
    }
}
