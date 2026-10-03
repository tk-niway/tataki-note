import SwiftUI

/// 設定画面の「一般」。
struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            AutoShowSettingsSection(settings: settings)

            LabeledContent("テーマ") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("テーマ", selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                    .accessibilityIdentifier("settings.themePicker")
                    SettingDescription(text: "「システム」は、Mac の外観モード(ライト・ダーク)に合わせます。メニューバーのメニューは、どれを選んでも Mac の外観モードのままです。")
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            LabeledContent("起動") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("ログイン時に起動", isOn: launchAtLoginBinding)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("settings.launchAtLoginToggle")
                    if let error = launchAtLogin.lastError {
                        LaunchAtLoginErrorNote(error: error)
                    }
                    if launchAtLogin.needsApproval {
                        LaunchAtLoginApprovalNote(onOpenSystemSettings: { launchAtLogin.openSystemSettings() })
                    }
                    SettingDescription(text: "オンにすると、Mac にログインしたときに TatakiNote が起動します。システム設定の「ログイン項目」で外したときは、ここもオフになります。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("メニューバー") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("メニューバーのアイコンを隠す", isOn: $settings.hidesMenuBarIcon)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("settings.hideMenuBarIconToggle")
                    SettingDescription(text: "隠している間は、TatakiNote をもう一度開く(Finder・Spotlight など)と、この設定画面が開きます。ホットキーと自動表示は今までどおり使えます。終了するときは、左下の「TatakiNote を終了」を押します。")
                }
            }
        }
        .formStyle(.columns)
        .settingsDetailPadding()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }
}

private struct LaunchAtLoginErrorNote: View {
    let error: LaunchAtLoginError

    var body: some View {
        SettingErrorNote(text: message, identifier: "settings.launchAtLoginError")
    }

    private var message: LocalizedStringKey {
        switch error {
        case .registerFailed:
            "ログイン項目に登録できませんでした。TatakiNote をアプリケーションフォルダから開いているか確かめて、もう一度オンにしてください。"
        case .unregisterFailed:
            "ログイン項目から外せませんでした。システム設定の「ログイン項目」で TatakiNote を外してください。"
        }
    }
}

private struct LaunchAtLoginApprovalNote: View {
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Text("システム設定の「ログイン項目」で TatakiNote を許可してください。許可するまで、ログイン時に起動しません。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            Button("システム設定を開く", action: onOpenSystemSettings)
                .controlSize(.small)
                .accessibilityIdentifier("settings.launchAtLoginOpenSettings")
        }
    }
}
