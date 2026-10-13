import SwiftUI

/// 設定画面の「一般」。
struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLoginModel
    let history: HistorySettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "外観", identifier: "settings.group.appearance") {
                SettingsCard {
                    themeRow
                }
            }
            SettingsGroup(title: "起動とメニューバー", identifier: "settings.group.startup") {
                SettingsCard {
                    launchAtLoginRow
                    hideMenuBarIconRow
                }
            }
            SettingsGroup(title: "履歴", identifier: "settings.group.history") {
                SettingsCard {
                    HistoryRow(history: history)
                }
            }
        }
        .settingsDetailPadding()
    }

    private var themeRow: some View {
        SettingsRow(
            title: "テーマ",
            description: "「システム」は、Mac の外観モード(ライト・ダーク)に合わせます。メニューバーのメニューは、どれを選んでも Mac の外観モードのままです。"
        ) {
            Picker("テーマ", selection: $settings.theme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("settings.themePicker")
        }
    }

    private var launchAtLoginRow: some View {
        VStack(spacing: 0) {
            SettingsRow(
                title: "ログイン時に起動",
                description: "オンにすると、Mac にログインしたときに TatakiNote が起動します。システム設定の「ログイン項目」で外したときは、ここもオフになります。"
            ) {
                Toggle("ログイン時に起動", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.launchAtLoginToggle")
            }
            if launchAtLogin.lastError != nil || launchAtLogin.needsApproval {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = launchAtLogin.lastError {
                        LaunchAtLoginErrorNote(error: error)
                    }
                    if launchAtLogin.needsApproval {
                        LaunchAtLoginApprovalNote(onOpenSystemSettings: { launchAtLogin.openSystemSettings() })
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var hideMenuBarIconRow: some View {
        SettingsRow(
            title: "メニューバーのアイコンを隠す",
            description: "隠している間は、TatakiNote をもう一度開く(Finder・Spotlight など)と、この設定画面が開きます。ホットキーと自動表示は今までどおり使えます。終了するときは、左下の「TatakiNote を終了」を押します。"
        ) {
            Toggle("メニューバーのアイコンを隠す", isOn: $settings.hidesMenuBarIcon)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier("settings.hideMenuBarIconToggle")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }
}

private struct HistoryRow: View {
    let history: HistorySettingsModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finishedSequence = 0
    @State private var displayedCount: Int?

    private static let warningText = "挿入の履歴をすべて削除しますか? この操作は元に戻せません。"
    private static let countdownInterval = Duration.milliseconds(45)

    private var isCountingDown: Bool {
        history.phase == .cleared && finishedSequence != history.clearedSequence
    }

    private var shownCount: Int {
        guard isCountingDown else { return history.historyCount }
        return displayedCount ?? history.clearedCount
    }

    var body: some View {
        SettingsRow {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("挿入した文章")
                            .font(.system(size: 13, weight: .medium))
                        Text(verbatim: String(shownCount))
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("settings.historyCount")
                        Text("件")
                            .font(.system(size: 13, weight: .medium))
                    }
                    description
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .animation(reduceMotion ? nil : popAnimation, value: history.phase)
        }
        .task(id: history.clearedSequence) {
            await runCountdown()
        }
    }

    @ViewBuilder
    private var description: some View {
        if history.phase == .confirming {
            SettingDescription(Self.warningText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.warningText)
                .accessibilityIdentifier("settings.clearHistoryWarning")
        } else {
            SettingDescription("挿入した文章は、最新 \(DraftLibrary.historyLimit) 件までこの Mac に残ります。")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch history.phase {
        case .idle:
            Button {
                animated { history.requestClear() }
            } label: {
                Text("履歴をすべて削除")
                    .foregroundStyle(.red)
            }
            .disabled(!history.isClearAvailable)
            .accessibilityIdentifier("settings.clearHistory")
        case .confirming:
            HStack(spacing: 6) {
                Button("キャンセル") {
                    animated { history.cancelClear() }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings.clearHistoryCancel")
                Button("削除する") {
                    animated { history.confirmClear() }
                }
                .buttonStyle(DestructiveButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("settings.clearHistoryConfirm")
            }
            .transition(.scale.combined(with: .opacity))
        case .cleared:
            if !isCountingDown {
                Text("✓ 削除しました")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.scale)
                    .accessibilityIdentifier("settings.clearHistoryDone")
            }
        }
    }

    private var popAnimation: Animation {
        .spring(duration: 0.3, bounce: 0.4)
    }

    private func animated(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : popAnimation, change)
    }

    private func runCountdown() async {
        let sequence = history.clearedSequence
        guard sequence > 0, history.phase == .cleared else { return }
        if !reduceMotion {
            for step in HistorySettingsModel.countdownSteps(from: history.clearedCount) {
                try? await Task.sleep(for: Self.countdownInterval)
                guard !Task.isCancelled, history.phase == .cleared, history.clearedSequence == sequence else {
                    displayedCount = nil
                    return
                }
                displayedCount = step
            }
        }
        displayedCount = nil
        animated { finishedSequence = sequence }
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.8 : 1))
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
