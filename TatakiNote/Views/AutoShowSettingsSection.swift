import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の「自動表示」と「対象のアプリ」の2項目。
struct AutoShowSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var editor: AutoShowAppsEditor

    init(settings: AppSettings) {
        self.settings = settings
        _editor = State(initialValue: AutoShowAppsEditor(settings: settings))
    }

    var body: some View {
        LabeledContent("自動表示") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("自動表示", selection: $settings.autoShowMode) {
                    ForEach(AutoShowMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityIdentifier("settings.autoShowModePicker")
                description("入力欄を選んだだけでパネルを開きます。ホットキーは今までどおり使えます。")
            }
        }
        .padding(.bottom, 12)

        LabeledContent("対象のアプリ") {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $editor.selection) {
                    ForEach(editor.rows()) { row in
                        HStack(spacing: 6) {
                            icon(for: row)
                            Text(row.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(height: 22)
                        .tag(row.id)
                        .accessibilityIdentifier("settings.autoShowApp.\(row.bundleIdentifier)")
                    }
                }
                .listStyle(.bordered)
                .frame(height: 88)
                .accessibilityIdentifier("settings.autoShowAppList")
                .disabled(!editor.isEditable)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(editor.candidates) { app in
                            Button(app.name) { editor.add(app) }
                        }
                        Divider()
                        Button("その他…") { chooseOtherApplication() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .controlSize(.small)
                    .frame(width: 24)
                    .accessibilityLabel("追加")
                    .accessibilityIdentifier("settings.autoShowAppAdd")
                    .disabled(!editor.isEditable)

                    Button {
                        editor.removeSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 24)
                    .accessibilityLabel("外す")
                    .accessibilityIdentifier("settings.autoShowAppRemove")
                    .disabled(!editor.canRemove)
                }

                description("「＋」で起動中のアプリから追加します。起動していないアプリは「その他…」から選べます。")
            }
        }
    }

    @ViewBuilder
    private func icon(for row: AutoShowAppRow) -> some View {
        if let url = row.applicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
        }
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

    private func description(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
