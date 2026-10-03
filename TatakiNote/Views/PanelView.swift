import AppKit
import SwiftUI

/// パネルの中身。
struct PanelView: View {
    @Bindable var model: PanelModel
    let settings: AppSettings
    let onKeyInput: (PanelKeyInput) -> Bool
    let onClose: () -> Void

    private static let placeholderInset = NSSize(
        width: PanelMetrics.textContainerInset.width + NSTextContainer().lineFragmentPadding,
        height: PanelMetrics.textContainerInset.height
    )

    private static let closeButtonHitSize: CGFloat = 20

    private static let titleText = "TatakiNote"

    var body: some View {
        let font = settings.panelFont
        let content = statusBarContent
        VStack(spacing: 0) {
            PromptTextEditor(text: $model.text, focusRequest: model.focusRequest, font: font, onKeyInput: onKeyInput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("ここにプロンプトを書く…")
                            .font(Font(font as CTFont))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, Self.placeholderInset.width)
                            .padding(.top, Self.placeholderInset.height)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            if !content.isEmpty {
                Divider()
                PanelStatusBar(content: content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .windowStyle(theme: settings.theme, opacity: settings.panelOpacity)
        .overlay(alignment: .top) {
            Text(Self.titleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: PanelMetrics.titleBarHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.leading, 8)
                .padding(.top, (PanelMetrics.titleBarHeight - Self.closeButtonHitSize) / 2)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .frame(width: Self.closeButtonHitSize, height: Self.closeButtonHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(CloseButtonStyle())
        .focusable(false)
        .help("閉じる(下書きは残ります)")
        .accessibilityLabel("閉じる")
        .accessibilityIdentifier("promptPanel.closeButton")
    }

    private struct CloseButtonStyle: ButtonStyle {
        @State private var isHovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(configuration.isPressed ? .primary : (isHovering ? .secondary : .tertiary))
                .onHover { isHovering = $0 }
        }
    }

    private var statusBarContent: PanelStatusBarContent {
        PanelStatusBarContent(
            text: model.text,
            items: settings.panelStatusItems,
            commitKeyText: settings.commitKeyDisplayText,
            commitAndSendKeyText: settings.commitAndSendKeyDisplayText
        )
    }
}
