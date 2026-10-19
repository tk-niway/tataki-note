import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の「自動で開く」のまとまり(自動表示と対象のアプリ)。
struct AutoShowSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var editor: AutoShowAppsEditor

    init(settings: AppSettings) {
        self.settings = settings
        _editor = State(initialValue: AutoShowAppsEditor(settings: settings))
    }

    var body: some View {
        SettingsGroup(title: "自動で開く", identifier: "settings.group.autoShow") {
            SettingsCard {
                modeRow
                appsRow
            }
        }
    }

    private var modeRow: some View {
        SettingsRow(
            title: "自動表示",
            description: SettingsHelpText.autoShowMode
        ) {
            Picker("自動表示", selection: $settings.autoShowMode) {
                ForEach(AutoShowMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("settings.autoShowModePicker")
        }
    }

    private var appsRow: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("対象のアプリ")
                        .font(.system(size: 13, weight: .medium))
                    SettingDescription(SettingsHelpText.autoShowApps)
                }
                FlowLayout(spacing: 6) {
                    ForEach(editor.rows()) { row in
                        AutoShowAppChip(row: row, canEdit: editor.canEdit) {
                            editor.remove(bundleIdentifier: row.bundleIdentifier)
                        }
                    }
                    addMenu
                }
                .opacity(editor.canEdit ? 1 : 0.5)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.autoShowAppList")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(editor.candidates) { app in
                Button(app.name) { editor.add(app) }
            }
            Divider()
            Button("その他…") { chooseOtherApplication() }
        } label: {
            Text("＋ 追加")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!editor.canEdit)
        .accessibilityLabel("追加")
        .accessibilityIdentifier("settings.autoShowAppAdd")
    }

    private func chooseOtherApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.addApplication(at: url)
    }
}

private struct AutoShowAppChip: View {
    let row: AutoShowAppRow
    let canEdit: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            icon
            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel("\(row.name) を外す")
            .accessibilityIdentifier("settings.autoShowApp.\(row.bundleIdentifier).remove")
        }
        .padding(.leading, 4)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.14)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.autoShowApp.\(row.bundleIdentifier)")
    }

    @ViewBuilder
    private var icon: some View {
        if let url = row.applicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
