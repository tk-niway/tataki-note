import SwiftUI

/// 設定画面の「パネル」。
struct PanelSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: EditorSettingsModel
    @Bindable var panelDefaultSize: PanelDefaultSizeModel
    let onShowFontPanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            screenGroup
            fontAndOpacityGroup
            defaultSizeGroup
            statusItemsGroup
            outlineGroup
            animationGroup
        }
        .settingsDetailPadding()
    }

    // MARK: - パネルを出す位置

    private var screenGroup: some View {
        SettingsGroup(title: "パネルを出す位置", identifier: "settings.group.panelScreen") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(PanelScreen.allCases, id: \.self) { screen in
                        PanelScreenTile(
                            screen: screen,
                            isSelected: settings.effectivePanelScreen == screen,
                            isEnabled: screen.isSelectable(isNoteMode: settings.isNoteMode),
                            onSelect: { select(screen) }
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("パネルを出す位置")
                .accessibilityIdentifier("settings.panelScreenPicker")
                if settings.isNoteMode {
                    NoteModeReason(restriction: .nearFocusedField, identifier: "settings.noteModeReason.nearFocusedField")
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - フォントと透明度

    private var fontAndOpacityGroup: some View {
        SettingsGroup(title: "フォントと透明度", identifier: "settings.group.fontAndOpacity") {
            SettingsCard {
                fontRow
                fontSizeRow
                opacityRow
            }
        }
    }

    private var fontRow: some View {
        PanelSettingsRowContainer {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("フォント")
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: model.fontDisplayName)
                        .font(Font(model.fontNameFont))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.fontName")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("システムフォントに戻す") {
                    model.resetFontToSystem()
                }
                .disabled(model.isSystemFont)
                .accessibilityIdentifier("settings.resetFontToSystem")
                Button("変更…") {
                    onShowFontPanel()
                }
                .accessibilityIdentifier("settings.showFontPanel")
            }
        }
    }

    private var fontSizeRow: some View {
        SettingsRow(title: "文字サイズ") {
            HStack(spacing: 6) {
                Text(verbatim: model.fontSizeText)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityIdentifier("settings.fontSizeValue")
                Stepper(value: $settings.panelFontSize, in: PanelTextStyle.fontSizeRange, step: 1) {
                    Text("文字サイズ")
                }
                .labelsHidden()
                .accessibilityIdentifier("settings.fontSizeStepper")
            }
        }
    }

    private var opacityRow: some View {
        SettingsRow(title: "透明度", description: EditorSettingsModel.opacityDescription) {
            HStack(spacing: 8) {
                Slider(value: $settings.panelOpacity, in: PanelTextStyle.opacityRange, step: 0.05) {
                    Text("透明度")
                }
                .labelsHidden()
                .frame(width: 160)
                .accessibilityIdentifier("settings.opacitySlider")
                Text(verbatim: model.opacityPercentText)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityIdentifier("settings.opacityValue")
            }
        }
    }

    // MARK: - パネルのサイズ

    private var defaultSizeGroup: some View {
        SettingsGroup(title: "パネルのサイズ", identifier: "settings.group.panelDefaultSize") {
            SettingsCard {
                SettingsRow(title: "幅 × 高さ") {
                    HStack(spacing: 12) {
                        PanelDefaultLengthField(
                            label: "幅",
                            value: $panelDefaultSize.width,
                            range: PanelDefaultSizeModel.widthRange,
                            fieldIdentifier: "settings.panelDefaultWidthField",
                            stepperIdentifier: "settings.panelDefaultWidthStepper"
                        )
                        PanelDefaultLengthField(
                            label: "高さ",
                            value: $panelDefaultSize.height,
                            range: PanelDefaultSizeModel.heightRange,
                            fieldIdentifier: "settings.panelDefaultHeightField",
                            stepperIdentifier: "settings.panelDefaultHeightStepper"
                        )
                    }
                }
                heldSizeRow
            }
        }
    }

    private var heldSizeRow: some View {
        PanelSettingsRowContainer {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    panelDefaultSize.useCurrentPanelSize()
                } label: {
                    Text("今のパネルサイズを既定にする")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.17)))
                }
                .buttonStyle(.plain)
                .disabled(!panelDefaultSize.canUseCurrentPanelSize)
                .opacity(panelDefaultSize.canUseCurrentPanelSize ? 1 : 0.4)
                .accessibilityIdentifier("settings.useCurrentPanelSize")
                Button("初期値に戻す") {
                    panelDefaultSize.resetToInitial()
                }
                .accessibilityIdentifier("settings.resetPanelDefaultSize")
            }
        }
    }

    // MARK: - 帯に出す項目

    private var statusItemsGroup: some View {
        SettingsGroup(
            title: "帯に出す項目",
            footer: SettingsHelpText.statusItemsFooter,
            identifier: "settings.group.statusItems"
        ) {
            SettingsCard {
                ForEach(PanelStatusItem.allCases, id: \.self) { item in
                    statusItemRow(item)
                }
            }
        }
    }

    private func statusItemRow(_ item: PanelStatusItem) -> some View {
        PanelSettingsRowContainer {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.displayName)
                        .font(.system(size: 13, weight: .medium))
                    if let note = model.statusItemNote(item) {
                        let noteText = statusItemNoteText(note)
                        SettingDescription(noteText)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(noteText)
                            .accessibilityIdentifier("settings.statusItemNote.\(item.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(item.displayName, isOn: statusItemBinding(item))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.statusItem.\(item.rawValue)")
            }
        }
    }

    // MARK: - 挿入先の枠線・アニメーション

    private var outlineGroup: some View {
        SettingsGroup(title: "挿入先の枠線", identifier: "settings.group.insertionTargetOutline") {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        title: "挿入先の入力欄を枠線で囲む",
                        description: SettingsHelpText.insertionTargetOutline
                    ) {
                        Toggle("挿入先の入力欄を枠線で囲む", isOn: $settings.isInsertionTargetOutlineShown)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.isNoteMode)
                            .accessibilityIdentifier("settings.insertionTargetOutlineToggle")
                    }
                    if settings.isNoteMode {
                        NoteModeReason(restriction: .insertionTargetOutline, identifier: "settings.noteModeReason.insertionTargetOutline")
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
            }
        }
    }

    private var animationGroup: some View {
        SettingsGroup(title: "アニメーション", identifier: "settings.group.animation") {
            SettingsCard {
                SettingsRow(title: "パネルの開閉エフェクト") {
                    Toggle("パネルの開閉エフェクト", isOn: $settings.isPanelAnimationEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.panelAnimationToggle")
                }
            }
        }
    }

    // MARK: - 操作

    private func statusItemNoteText(_ note: StatusItemNote) -> String {
        switch note {
        case .keyNotAssigned: String(localized: "キーを登録していないあいだは帯に出ません")
        case .noteMode: String(localized: "ノートモードのあいだは帯に出ません")
        }
    }

    private func select(_ screen: PanelScreen) {
        guard screen.isSelectable(isNoteMode: settings.isNoteMode) else { return }
        settings.panelScreen = screen
    }

    private func statusItemBinding(_ item: PanelStatusItem) -> Binding<Bool> {
        Binding(
            get: { model.isStatusItemVisible(item) },
            set: { model.setStatusItem(item, isVisible: $0) }
        )
    }
}

private struct PanelSettingsRowContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PanelDefaultLengthField: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let fieldIdentifier: String
    let stepperIdentifier: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            TextField(label, value: $value, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .accessibilityIdentifier(fieldIdentifier)
            Stepper(value: $value, in: range, step: PanelDefaultSizeModel.step) {
                Text(label)
            }
            .labelsHidden()
            .accessibilityIdentifier(stepperIdentifier)
        }
        .fixedSize()
    }
}
