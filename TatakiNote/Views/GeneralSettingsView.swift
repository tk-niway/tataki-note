import KeyboardShortcuts
import SwiftUI

/// @note p0-606
struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var keySettings: PanelKeySettingsModel
    let launchAtLogin: LaunchAtLoginModel

    var body: some View {
        Form {
            LabeledContent("パネルを開く・閉じる") {
                VStack(alignment: .leading, spacing: 6) {
                    // @note p0-607
                    KeyboardShortcuts.Recorder("パネルを開く・閉じる", name: .togglePanel)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.hotkeyRecorder")
                    SettingDescription(text: "どのアプリを使っているときでも、このキーでパネルを開く・閉じるを切り替えます。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("確定キー") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRecorder(for: .commit, recorderID: "settings.commitKeyRecorder", rejectionID: "settings.commitKeyRejection")
                    SettingDescription(text: "パネルでこのキーを押すと、書いた文章を元のアプリに挿入します(送信はしません)。修飾キー(⌘・⌥・⌃・⇧)と組み合わせたキーを登録できます。登録していない Enter は改行になります。初期設定では登録していません。登録していないときは、確定+送信キーでだけ挿入します。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("確定+送信キー") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRecorder(for: .commitAndSend, recorderID: "settings.commitAndSendKeyRecorder", rejectionID: "settings.commitAndSendKeyRejection")
                    SettingDescription(text: "パネルでこのキーを押すと、書いた文章を挿入したあと、挿入先で Enter を送って送信します。初期設定は ⌘↩ です。送信は取り消せないので、送信せずに挿入したいときは確定キーを登録してください。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("パネルを出す位置") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("パネルを出す位置", selection: $settings.panelScreen) {
                        ForEach(PanelScreen.allCases, id: \.self) { panelScreen in
                            Text(panelScreen.displayName).tag(panelScreen)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.panelScreenPicker")
                    SettingDescription(text: "パネルを新しく開くときに出す位置です。「入力欄の近く」は、挿入先のアプリで選ばれている入力欄の近くに出します。入力欄の位置が分からないときは、挿入先のウィンドウがある画面の中央に出します。ほかの3つは、その画面の中央に出します(挿入先のウィンドウが分からないときは、マウスのある画面)。「メインの画面」は、システム設定の「ディスプレイ」でメインディスプレイにしている画面です。")
                }
            }
            .padding(.bottom, 12)

            AutoShowSettingsSection(settings: settings)

            // @note p0-609
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
                    // @note p0-610
                    Toggle("ログイン時に起動", isOn: launchAtLoginBinding)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("settings.launchAtLoginToggle")
                    // @note p0-611
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

    /// @note p0-612
    private func shortcutRecorder(for role: PanelShortcutRole, recorderID: String, rejectionID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelShortcutRecorder(
                displayText: keySettings.displayText(for: role),
                isRecording: keySettings.recordingRole == role,
                isRecordingNow: { keySettings.recordingRole == role },
                onBeginRecording: { keySettings.beginRecording(role) },
                onRecord: { keySettings.record($0, for: role) },
                onClear: { keySettings.clear(role) },
                onEndRecording: { keySettings.endRecording(role) },
                identifier: recorderID
            )
            .frame(width: 160, height: 22)
            if let message = keySettings.rejectionMessage(for: role) {
                PanelShortcutRejectionNote(message: message, identifier: rejectionID)
            }
        }
    }
}

/// @note p0-613
private struct PanelShortcutRejectionNote: View {
    let message: String
    let identifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// @note p0-614
private struct LaunchAtLoginErrorNote: View {
    let error: LaunchAtLoginError

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.launchAtLoginError")
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

/// @note p0-615
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
