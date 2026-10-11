import SwiftUI

/// 設定画面の「パネル」。
struct PanelSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: EditorSettingsModel
    @Bindable var panelDefaultSize: PanelDefaultSizeModel
    let onShowFontPanel: () -> Void

    var body: some View {
        Form {
            LabeledContent("パネルを出す位置") {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(PanelScreen.allCases, id: \.self) { panelScreen in
                            RadioOptionButton(
                                title: panelScreen.displayName,
                                isOn: settings.effectivePanelScreen == panelScreen,
                                isEnabled: isSelectable(panelScreen),
                                action: { select(panelScreen) }
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("パネルを出す位置")
                    .accessibilityIdentifier("settings.panelScreenPicker")
                    if settings.isNoteMode {
                        NoteModeReason(restriction: .nearFocusedField, identifier: "settings.noteModeReason.nearFocusedField")
                    }
                    SettingDescription(text: "パネルを新しく開くときに出す位置です。「入力欄の近く」は、挿入先のアプリで選ばれている入力欄の近くに出します。入力欄の位置が分からないときは、挿入先のウィンドウがある画面の中央に出します。「マウスの近く」は、マウスポインタのすぐ下に出します。「挿入先のウィンドウがある画面」と「メインの画面」は、その画面の中央に出します(挿入先のウィンドウが分からないときは、マウスのある画面)。「メインの画面」は、システム設定の「ディスプレイ」でメインディスプレイにしている画面です。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("フォント") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: model.fontDisplayName)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.fontName")
                    VStack(alignment: .leading, spacing: 8) {
                        Button("フォントパネルを開く") {
                            onShowFontPanel()
                        }
                        .accessibilityIdentifier("settings.showFontPanel")
                        Button("システムフォントに戻す") {
                            model.resetFontToSystem()
                        }
                        .disabled(model.isSystemFont)
                        .accessibilityIdentifier("settings.resetFontToSystem")
                    }
                    SettingDescription(text: "パネルの入力欄の文字に使います。フォントパネルで選んだフォントと太さが、すぐに使われます。フォントパネルで変えた大きさは「文字サイズ」にも入ります。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("文字サイズ") {
                VStack(alignment: .leading, spacing: 6) {
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
                    SettingDescription(EditorSettingsModel.fontSizeDescription)
                }
            }
            .padding(.bottom, 12)

            LabeledContent("透明度") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacity, in: PanelTextStyle.opacityRange, step: 0.05) {
                            Text("透明度")
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("settings.opacitySlider")
                        Text(verbatim: model.opacityPercentText)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                            .accessibilityIdentifier("settings.opacityValue")
                    }
                    SettingDescription(EditorSettingsModel.opacityDescription)
                }
            }
            .padding(.bottom, 12)

            LabeledContent("パネルの既定の大きさ") {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
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
                        Button("今のパネルの大きさを既定にする") {
                            panelDefaultSize.useCurrentPanelSize()
                        }
                        .disabled(!panelDefaultSize.canUseCurrentPanelSize)
                        .accessibilityIdentifier("settings.useCurrentPanelSize")
                        Button("初期値に戻す") {
                            panelDefaultSize.resetToInitial()
                        }
                        .accessibilityIdentifier("settings.resetPanelDefaultSize")
                    }
                    SettingDescription(PanelDefaultSizeModel.rangeDescription)
                    SettingDescription(PanelDefaultSizeModel.heldSizeDescription)
                }
            }
            .padding(.bottom, 12)

            LabeledContent("帯に出す項目") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PanelStatusItem.allCases, id: \.self) { item in
                        Toggle(item.displayName, isOn: statusItemBinding(item))
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("settings.statusItem.\(item.rawValue)")
                        if let note = model.statusItemNote(item) {
                            SettingDescription(statusItemNoteText(note))
                                .padding(.leading, 20)
                                .accessibilityIdentifier("settings.statusItemNote.\(item.rawValue)")
                        }
                    }
                    SettingDescription(text: "パネルの下の帯に出す項目です。すべて外すと帯ごと消え、そのぶん入力欄が広がります。")
                }
            }

            LabeledContent("挿入先の枠線") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("挿入先の入力欄を枠線で囲む", isOn: $settings.isInsertionTargetOutlineShown)
                        .toggleStyle(.checkbox)
                        .disabled(settings.isNoteMode)
                        .accessibilityIdentifier("settings.insertionTargetOutlineToggle")
                    if settings.isNoteMode {
                        NoteModeReason(restriction: .insertionTargetOutline, identifier: "settings.noteModeReason.insertionTargetOutline")
                    }
                    SettingDescription(text: "パネルを開いている間、文章が入る入力欄を枠線で囲みます。オフにしても、タイトルバーの挿入先の表示と「挿入先なし」の表示、確定したときの動きは変わりません。")
                }
            }
            .padding(.top, 12)

            LabeledContent("アニメーション") {
                Toggle("パネルの開閉エフェクト", isOn: $settings.isPanelAnimationEnabled)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("settings.panelAnimationToggle")
            }
            .padding(.top, 12)
        }
        .formStyle(.columns)
        .settingsDetailPadding()
    }

    private func statusItemNoteText(_ note: StatusItemNote) -> String {
        switch note {
        case .keyNotAssigned: String(localized: "キーを登録していないあいだは帯に出ません")
        case .noteMode: String(localized: "ノートモードのあいだは帯に出ません")
        }
    }

    private func isSelectable(_ panelScreen: PanelScreen) -> Bool {
        !(settings.isNoteMode && panelScreen == .nearFocusedField)
    }

    private func select(_ panelScreen: PanelScreen) {
        guard isSelectable(panelScreen) else { return }
        settings.panelScreen = panelScreen
    }

    private func statusItemBinding(_ item: PanelStatusItem) -> Binding<Bool> {
        Binding(
            get: { model.isStatusItemVisible(item) },
            set: { model.setStatusItem(item, isVisible: $0) }
        )
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
    }
}
