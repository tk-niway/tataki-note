import SwiftUI

/// 設定画面の「エディタ設定」。
struct EditorSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: EditorSettingsModel
    @Bindable var panelDefaultSize: PanelDefaultSizeModel
    let onShowFontPanel: () -> Void

    var body: some View {
        Form {
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
                    SettingDescription(text: "10〜32 pt の間で選べます。")
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
                    SettingDescription(text: "パネル全体(背景と文字)の透け具合です。100% で透けません。40% より下にはできません。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("パネルの既定の大きさ") {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Text("幅")
                                TextField("幅", value: $panelDefaultSize.width, format: .number.grouping(.never))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(width: 56)
                                    .accessibilityIdentifier("settings.panelDefaultWidthField")
                                Stepper(
                                    value: $panelDefaultSize.width,
                                    in: PanelDefaultSizeModel.widthRange,
                                    step: PanelDefaultSizeModel.step
                                ) {
                                    Text("幅")
                                }
                                .labelsHidden()
                                .accessibilityIdentifier("settings.panelDefaultWidthStepper")
                            }
                            HStack(spacing: 6) {
                                Text("高さ")
                                TextField("高さ", value: $panelDefaultSize.height, format: .number.grouping(.never))
                                    .labelsHidden()
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(width: 56)
                                    .accessibilityIdentifier("settings.panelDefaultHeightField")
                                Stepper(
                                    value: $panelDefaultSize.height,
                                    in: PanelDefaultSizeModel.heightRange,
                                    step: PanelDefaultSizeModel.step
                                ) {
                                    Text("高さ")
                                }
                                .labelsHidden()
                                .accessibilityIdentifier("settings.panelDefaultHeightStepper")
                            }
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
                    SettingDescription(text: "パネルを開いたときの大きさです(幅 320〜4000・高さ 160〜4000 pt)。変えると、次にパネルを開いたときから使います。")
                    SettingDescription(text: "パネルの端をドラッグして大きさを変えると、文章を挿入するまではその大きさで開きます(その間は、ここを変えてもパネルの大きさは変わりません)。「今のパネルの大きさを既定にする」は、ドラッグで大きさを変えた後に押せて、ドラッグで決めた大きさを既定にします(文章で伸びた高さは含みません)。")
                }
            }
            .padding(.bottom, 12)

            LabeledContent("帯に出す項目") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PanelStatusItem.allCases, id: \.self) { item in
                        Toggle(item.displayName, isOn: statusItemBinding(item))
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("settings.statusItem.\(item.rawValue)")
                        if model.statusItemNote(item) == .keyNotAssigned {
                            SettingDescription(text: "キーを登録していないあいだは帯に出ません")
                                .padding(.leading, 20)
                                .accessibilityIdentifier("settings.statusItemNote.\(item.rawValue)")
                        }
                    }
                    SettingDescription(text: "パネルの下の帯に出す項目です。すべて外すと帯ごと消え、そのぶん入力欄が広がります。")
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
                    SettingDescription(text: "パネルの入力欄で使えるキーです(割り当ては変えられません)。改行・閉じる・確定のキーは、パネルの下の帯と「一般」で確かめられます。")
                }
            }
        }
        .formStyle(.columns)
        .settingsDetailPadding()
    }

    private func statusItemBinding(_ item: PanelStatusItem) -> Binding<Bool> {
        Binding(
            get: { model.isStatusItemVisible(item) },
            set: { model.setStatusItem(item, isVisible: $0) }
        )
    }
}
