import KeyboardShortcuts
import SwiftUI

/// 設定画面の「ホットキーとキー操作」。
struct KeySettingsView: View {
    let settings: AppSettings
    @Bindable var keySettings: PanelKeySettingsModel
    let onSwitchToInsert: () -> Void

    private var isNoteMode: Bool { settings.isNoteMode }

    private var shortcutGroupRows: [[EditorShortcutGroup]] {
        let groups = EditorShortcuts.groups
        return stride(from: 0, to: groups.count, by: 2).map { start in
            Array(groups[start..<min(start + 2, groups.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hotkeyGroup
            AutoShowSettingsSection(settings: settings, onSwitchToInsert: onSwitchToInsert)
            insertAndSendGroup
            shortcutsGroup
        }
        .settingsDetailPadding()
    }

    private var hotkeyGroup: some View {
        SettingsGroup(title: "ホットキーで開く", identifier: "settings.group.hotkey") {
            SettingsCard {
                RecorderRow(
                    title: "パネルを開く・閉じる",
                    description: "どのアプリを使っているときでも、このキーでパネルを開く・閉じるを切り替えます。",
                    rejectionMessage: keySettings.hotkeyRejectionMessage,
                    rejectionIdentifier: "settings.hotkeyRejection"
                ) {
                    KeyboardShortcuts.Recorder("パネルを開く・閉じる", name: .togglePanel) { shortcut in
                        keySettings.hotkeyDidChange(to: shortcut.map { PanelShortcut($0) })
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.hotkeyRecorder")
                    .recorderFeedback(keySettings.hotkeyFeedback)
                }
            }
        }
    }

    private var insertAndSendGroup: some View {
        SettingsGroup(
            title: "挿入と送信",
            badge: "インサートのみ",
            footer: "記録ボックスをクリックして、新しい組み合わせを押します。esc で取り消します。",
            identifier: "settings.group.insertAndSend"
        ) {
            InsertOnlyGate(group: .insertAndSend, isNoteMode: isNoteMode, onSwitchToInsert: onSwitchToInsert) {
                SettingsCard {
                    shortcutRecorderRow(
                        title: "確定+挿入キー",
                        role: .commit,
                        recorderID: "settings.commitKeyRecorder",
                        rejectionID: "settings.commitKeyRejection"
                    )
                    shortcutRecorderRow(
                        title: "確定+送信キー",
                        role: .commitAndSend,
                        recorderID: "settings.commitAndSendKeyRecorder",
                        rejectionID: "settings.commitAndSendKeyRejection"
                    )
                }
            }
        }
    }

    private var shortcutsGroup: some View {
        SettingsGroup(
            title: "パネルの中で使えるキー",
            note: "変更できません",
            footer: EditorShortcuts.settingDescription(isNoteMode: isNoteMode),
            identifier: "settings.group.shortcuts"
        ) {
            VStack(spacing: 10) {
                ForEach(Array(shortcutGroupRows.enumerated()), id: \.offset) { _, groups in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(groups) { group in
                            ShortcutGroupCard(group: group)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.shortcutList")
        }
    }

    private func shortcutRecorderRow(
        title: String.LocalizationValue,
        role: PanelShortcutRole,
        recorderID: String,
        rejectionID: String
    ) -> some View {
        let titleText = String(localized: title)
        return RecorderRow(
            title: LocalizedStringKey(titleText),
            description: role.settingDescription,
            rejectionMessage: keySettings.rejectionMessage(for: role),
            rejectionIdentifier: rejectionID
        ) {
            PanelShortcutRecorder(
                display: keySettings.recorderDisplay(for: role),
                feedback: keySettings.feedback[role],
                onBeginRecording: { keySettings.beginRecording(role) },
                onRecord: { keySettings.record($0, for: role) },
                onClear: { keySettings.clear(role) },
                onEndRecording: { keySettings.endRecording(role) },
                identifier: recorderID,
                accessibilityLabel: titleText
            )
        }
    }
}

private struct RecorderRow<Recorder: View>: View {
    let title: LocalizedStringKey
    let description: String
    let rejectionMessage: String?
    let rejectionIdentifier: String
    @ViewBuilder let recorder: Recorder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: title, description: description) {
                recorder
            }
            if let rejectionMessage {
                SettingErrorNote(rejectionMessage, identifier: rejectionIdentifier)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
}

private struct ShortcutGroupCard: View {
    let group: EditorShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: group.title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 6)
                .accessibilityIdentifier("settings.shortcutGroup.\(group.id).title")
            ForEach(Array(group.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                if index > 0 {
                    Divider()
                }
                ShortcutRow(shortcut: shortcut, identifier: identifier(for: shortcut))
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.shortcutGroup.\(group.id)")
    }

    private func identifier(for shortcut: EditorShortcut) -> String {
        let isPanelCommand = EditorShortcuts.panelCommands.contains { $0.id == shortcut.id }
        return isPanelCommand ? "settings.panelCommand.\(shortcut.id)" : "settings.shortcut.\(shortcut.id)"
    }
}

private struct ShortcutRow: View {
    let shortcut: EditorShortcut
    let identifier: String

    var body: some View {
        let alternatives = KeyCaps.alternatives(in: shortcut.keys)
        Group {
            if alternatives.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    actionText
                    KeyCapRow(alternatives: alternatives)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    actionText
                    KeyCapRow(alternatives: alternatives)
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(shortcut.keys) \(shortcut.action)"))
        .accessibilityIdentifier(identifier)
    }

    private var actionText: some View {
        Text(verbatim: shortcut.action)
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
