import KeyboardShortcuts
import SwiftUI

/// 設定画面の「キー」。
struct KeySettingsView: View {
    @Bindable var keySettings: PanelKeySettingsModel

    var body: some View {
        Form {
            LabeledContent("パネルを開く・閉じる") {
                VStack(alignment: .leading, spacing: 6) {
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
                    SettingDescription(PanelShortcutRole.commit.settingDescription)
                }
            }
            .padding(.bottom, 12)

            LabeledContent("確定+送信キー") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRecorder(for: .commitAndSend, recorderID: "settings.commitAndSendKeyRecorder", rejectionID: "settings.commitAndSendKeyRejection")
                    SettingDescription(PanelShortcutRole.commitAndSend.settingDescription)
                }
            }
            .padding(.bottom, 12)

            LabeledContent("ショートカットキー") {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(EditorShortcuts.all) { shortcut in
                            if shortcut.id != EditorShortcuts.all.first?.id {
                                Divider()
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(verbatim: shortcut.keys)
                                    .frame(width: 96, alignment: .leading)
                                Text(verbatim: shortcut.action)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("settings.shortcut.\(shortcut.id)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.shortcutList")
                    SettingDescription(EditorShortcuts.settingDescription)
                }
            }
        }
        .formStyle(.columns)
        .settingsDetailPadding()
    }

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
                SettingErrorNote(message, identifier: rejectionID)
            }
        }
    }
}
