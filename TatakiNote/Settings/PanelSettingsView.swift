import SwiftUI

/// 設定画面の「パネル」。
struct PanelSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: EditorSettingsModel
    @Bindable var panelDefaultSize: PanelDefaultSizeModel
    @Bindable var pointerModel: PanelPointerSettingsModel
    let onShowFontPanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            screenGroup
            fontAndOpacityGroup
            editorTextGroup
            editorCaretGroup
            defaultSizeGroup
            pointerGroup
            statusItemsGroup
            outlineGroup
        }
        .settingsDetailPadding()
    }

    // MARK: - パネルを出す位置

    private var screenGroup: some View {
        SettingsGroup(title: "パネルを出す位置", identifier: "settings.group.panelScreen") {
            HStack(alignment: .top, spacing: 8) {
                ForEach(PanelScreen.allCases, id: \.self) { screen in
                    PanelScreenTile(
                        screen: screen,
                        isSelected: settings.panelScreen == screen,
                        isEnabled: true,
                        onSelect: { settings.panelScreen = screen }
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("パネルを出す位置")
            .accessibilityIdentifier("settings.panelScreenPicker")
        }
    }

    // MARK: - フォントと透明度

    private var fontAndOpacityGroup: some View {
        SettingsGroup(title: "フォントと透明度", identifier: "settings.group.fontAndOpacity") {
            SettingsCard {
                fontRow
                fontSizeRow
                opacityRow
                bottomPaddingRow
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

    private var bottomPaddingRow: some View {
        SettingsRow(title: "最終行の下の余白", description: EditorSettingsModel.bottomPaddingDescription) {
            HStack(spacing: 6) {
                Text(verbatim: model.bottomPaddingText)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityIdentifier("settings.bottomPaddingValue")
                Stepper(value: $settings.editorBottomPaddingLines, in: EditorBottomPadding.lineRange) {
                    Text("最終行の下の余白")
                }
                .labelsHidden()
                .accessibilityIdentifier("settings.bottomPaddingStepper")
            }
        }
    }

    // MARK: - 文章の見え方

    private var editorTextGroup: some View {
        SettingsGroup(title: "文章の見え方", identifier: "settings.group.editorText") {
            SettingsCard {
                SettingsRow(title: "行間") {
                    HStack(spacing: 6) {
                        Text(verbatim: model.lineHeightText)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityIdentifier("settings.lineHeightValue")
                        Stepper(
                            value: $settings.editorLineHeightMultiple,
                            in: EditorReadability.lineHeightMultipleRange,
                            step: EditorReadability.lineHeightMultipleStep
                        ) {
                            Text("行間")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.lineHeightStepper")
                    }
                }
                SettingsRow(title: "段落の間隔", description: EditorSettingsModel.paragraphSpacingDescription) {
                    HStack(spacing: 6) {
                        Text(verbatim: model.paragraphSpacingText)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityIdentifier("settings.paragraphSpacingValue")
                        Stepper(
                            value: $settings.editorParagraphSpacingLines,
                            in: EditorReadability.paragraphSpacingLinesRange,
                            step: EditorReadability.paragraphSpacingLinesStep
                        ) {
                            Text("段落の間隔")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.paragraphSpacingStepper")
                    }
                }
                SettingsRow(title: "字間", description: EditorSettingsModel.letterSpacingDescription) {
                    HStack(spacing: 6) {
                        Text(verbatim: model.letterSpacingText)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityIdentifier("settings.letterSpacingValue")
                        Stepper(
                            value: $settings.editorLetterSpacingPercent,
                            in: EditorReadability.letterSpacingPercentRange,
                            step: 1
                        ) {
                            Text("字間")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.letterSpacingStepper")
                    }
                }
                SettingsRow(title: "1行の長さの上限", description: EditorSettingsModel.maxLineLengthDescription) {
                    HStack(spacing: 6) {
                        Text(verbatim: model.maxLineLengthText)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityIdentifier("settings.maxLineLengthValue")
                        Stepper {
                            Text("1行の長さの上限")
                        } onIncrement: {
                            model.incrementMaxLineLength()
                        } onDecrement: {
                            model.decrementMaxLineLength()
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.maxLineLengthStepper")
                    }
                }
                SettingsRow(title: "折り返した行の字下げ", description: EditorSettingsModel.wrapIndentDescription) {
                    Toggle("折り返した行の字下げ", isOn: $settings.editorIndentsWrappedLines)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.wrapIndentToggle")
                }
            }
        }
    }

    // MARK: - カーソル

    private var editorCaretGroup: some View {
        SettingsGroup(title: "カーソル", identifier: "settings.group.editorCaret") {
            SettingsCard {
                SettingsRow(title: "カーソルの形") {
                    Picker("カーソルの形", selection: $settings.editorCaretShape) {
                        ForEach(EditorCaretShape.allCases, id: \.self) { shape in
                            Text(verbatim: shape.displayName).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings.caretShapePicker")
                }
                SettingsRow(title: "カーソルの太さ", description: EditorSettingsModel.caretWidthDescription) {
                    HStack(spacing: 6) {
                        Text(verbatim: model.caretWidthText)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .accessibilityIdentifier("settings.caretWidthValue")
                        Stepper(
                            value: $settings.editorCaretWidth,
                            in: EditorReadability.caretWidthRange,
                            step: 1
                        ) {
                            Text("カーソルの太さ")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.caretWidthStepper")
                    }
                }
                .disabled(!model.isCaretWidthEnabled)
                .opacity(model.isCaretWidthEnabled ? 1 : 0.4)
                SettingsRow(title: "今いる行のハイライト") {
                    Toggle("今いる行のハイライト", isOn: $settings.editorHighlightsCurrentLine)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.currentLineHighlightToggle")
                }
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

    // MARK: - 修飾キーで移動・サイズ変更

    private var pointerGroup: some View {
        SettingsGroup(
            title: "修飾キーで移動・サイズ変更",
            footer: PanelPointerSettingsModel.groupFooter,
            identifier: "settings.group.pointerModifiers"
        ) {
            SettingsCard {
                ForEach(PanelPointerAction.allCases, id: \.self) { action in
                    pointerRow(action)
                }
            }
            .id(pointerModel.rejectionCount)
        }
    }

    private func pointerRow(_ action: PanelPointerAction) -> some View {
        PanelSettingsRowContainer {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: PanelPointerSettingsModel.title(for: action))
                        .font(.system(size: 13, weight: .medium))
                    if pointerModel.isDisabled(action) {
                        let disabledText = PanelPointerSettingsModel.disabledText
                        SettingDescription(disabledText)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(disabledText)
                            .accessibilityIdentifier("settings.pointerModifierDisabled.\(action.rawValue)")
                    }
                    if let message = pointerModel.rejectionMessage(for: action) {
                        SettingErrorNote(
                            message,
                            identifier: "settings.pointerModifierRejected.\(action.rawValue)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    ForEach(PanelPointerModifier.allCases, id: \.self) { modifier in
                        Toggle(isOn: pointerBinding(modifier, for: action)) {
                            Text(verbatim: modifier.symbol)
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(modifier.accessibilityName)
                        .accessibilityIdentifier("settings.pointerModifier.\(action.rawValue).\(modifier.rawValue)")
                    }
                }
                .fixedSize()
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

    // MARK: - 挿入先の枠線

    private var outlineGroup: some View {
        SettingsGroup(title: "挿入先の枠線", identifier: "settings.group.insertionTargetOutline") {
            SettingsCard {
                SettingsRow(
                    title: "挿入先の入力欄を枠線で囲む",
                    description: SettingsHelpText.insertionTargetOutline
                ) {
                    Toggle("挿入先の入力欄を枠線で囲む", isOn: $settings.isInsertionTargetOutlineShown)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("settings.insertionTargetOutlineToggle")
                }
            }
        }
    }

    // MARK: - 操作

    private func statusItemNoteText(_ note: StatusItemNote) -> String {
        switch note {
        case .keyNotAssigned: String(localized: "キーを登録していないあいだは帯に出ません")
        }
    }

    private func pointerBinding(_ modifier: PanelPointerModifier, for action: PanelPointerAction) -> Binding<Bool> {
        Binding(
            get: { pointerModel.isOn(modifier, for: action) },
            set: { pointerModel.setModifier(modifier, isOn: $0, for: action) }
        )
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
