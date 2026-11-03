import AppKit
import SwiftUI

/// パネルの検索バー。検索の行と、置換の行(開いているとき)。
struct FindBarView: View {
    @Bindable var model: FindModel
    let onAction: (FindBarAction) -> Void
    @State private var focusedField: FindField?
    @Environment(\.isAppAnimationReduced) private var isReduced

    private static let rightClusterWidth: CGFloat = 128

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                findRow
                if model.isReplaceShown {
                    replaceRow
                        .transition(FindBarMotion.transition(isReduced: isReduced))
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 5)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            Divider()
        }
        .frame(height: FindBarMetrics.height(isVisible: true, isReplaceShown: model.isReplaceShown))
        .overlay(alignment: .bottomLeading) {
            errorNote
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findBar")
        .transition(FindBarMotion.transition(isReduced: isReduced))
    }

    // MARK: - 検索の行

    private var hasMatches: Bool {
        !model.matches.isEmpty
    }

    private var findRow: some View {
        HStack(spacing: 0) {
            toggleReplaceButton
            fieldBox(
                field: .find,
                text: $model.query,
                placeholder: "検索",
                identifier: "findBar.findField",
                isInvalid: model.isPatternInvalid,
                optionsWidth: 65
            ) {
                optionButton(.caseSensitive, label: "Aa", name: "大文字と小文字を区別する", key: "⌥⌘C", identifier: "findBar.caseSensitive")
                optionButton(.wholeWord, label: "ab", name: "単語単位で探す", key: "⌥⌘W", identifier: "findBar.wholeWord", underlined: true)
                optionButton(.regex, label: ".*", name: "正規表現を使う", key: "⌥⌘R", identifier: "findBar.regex")
            }
            .padding(.leading, 4)
            HStack(spacing: 0) {
                countLabel
                iconButton(
                    "arrow.up", fontSize: 12, help: "前の一致(⇧↩)", label: "前の一致",
                    identifier: "findBar.previous", action: .previous, isDisabled: !hasMatches
                )
                .padding(.leading, 2)
                iconButton(
                    "arrow.down", fontSize: 12, help: "次の一致(↩)", label: "次の一致",
                    identifier: "findBar.next", action: .next, isDisabled: !hasMatches
                )
                iconButton(
                    "xmark", fontSize: 11, help: "閉じる(esc)", label: "閉じる",
                    identifier: "findBar.close", action: .close
                )
                .padding(.leading, 4)
            }
            .padding(.leading, 6)
            .layoutPriority(1)
        }
        .frame(height: 24)
    }

    private var toggleReplaceButton: some View {
        Button(action: { onAction(.toggleReplace) }) {
            Image(systemName: model.isReplaceShown ? "chevron.down" : "chevron.right")
                .font(.system(size: 12))
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .help("置換の切り替え")
        .accessibilityLabel("置換")
        .accessibilityValue(model.isReplaceShown ? "開いています" : "閉じています")
        .accessibilityIdentifier("findBar.toggleReplace")
    }

    private var countLabel: some View {
        Text(verbatim: model.countText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 56, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.countText)
            .accessibilityIdentifier("findBar.matchCount")
    }

    // MARK: - 置換の行

    private var replaceRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 24, height: 1)
            fieldBox(
                field: .replace,
                text: $model.replacement,
                placeholder: "置換",
                identifier: "findBar.replaceField",
                isInvalid: false,
                optionsWidth: 23
            ) {
                optionButton(.preserveCase, label: "AB", name: "大文字と小文字を保持する", key: "⌥⌘P", identifier: "findBar.preserveCase")
            }
            HStack(spacing: 4) {
                textButton("置換", help: "次を置換(↩)", identifier: "findBar.replaceOne", action: .replaceOne)
                textButton("すべて置換", help: "すべて置換(⌘↩)", identifier: "findBar.replaceAll", action: .replaceAll)
            }
            .frame(width: Self.rightClusterWidth, alignment: .leading)
            .padding(.leading, 6)
            .layoutPriority(1)
        }
        .frame(height: 24)
    }

    // MARK: - 部品

    private func fieldBox<Options: View>(
        field: FindField,
        text: Binding<String>,
        placeholder: String,
        identifier: String,
        isInvalid: Bool,
        optionsWidth: CGFloat,
        @ViewBuilder options: () -> Options
    ) -> some View {
        FindBarTextField(
            text: text,
            model: model,
            findField: field,
            focusRequest: model.focusRequest,
            placeholder: placeholder,
            identifier: identifier,
            onFocusChange: { isFocused in
                if isFocused {
                    focusedField = field
                } else if focusedField == field {
                    focusedField = nil
                }
            }
        )
        .padding(.leading, 6)
        .padding(.trailing, optionsWidth)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
        .overlay(alignment: .trailing) {
            HStack(spacing: 1) {
                options()
            }
            .padding(.trailing, 3)
        }
        .overlay {
            fieldBorder(isFocused: focusedField == field, isInvalid: isInvalid)
        }
        .frame(minWidth: 120, maxWidth: .infinity)
    }

    @ViewBuilder
    private func fieldBorder(isFocused: Bool, isInvalid: Bool) -> some View {
        if isInvalid {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .systemRed), lineWidth: 1)
                .allowsHitTesting(false)
        } else if isFocused {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }

    private func optionButton(
        _ option: FindOption,
        label: String,
        name: LocalizedStringKey,
        key: String,
        identifier: String,
        underlined: Bool = false
    ) -> some View {
        let isOn = model.options.isOn(option)
        return Button(action: { onAction(.toggle(option)) }) {
            Text(verbatim: label)
                .font(.system(size: 11, weight: .medium))
                .underline(underlined)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(FindOptionToggleStyle(isOn: isOn))
        .focusable(false)
        .help(Text(name) + Text(verbatim: "(\(key))"))
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "オン" : "オフ")
        .accessibilityIdentifier(identifier)
    }

    private func iconButton(
        _ systemName: String,
        fontSize: CGFloat,
        help: LocalizedStringKey,
        label: LocalizedStringKey,
        identifier: String,
        action: FindBarAction,
        isDisabled: Bool = false
    ) -> some View {
        Button(action: { onAction(action) }) {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelIconButtonStyle())
        .focusable(false)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func textButton(
        _ title: LocalizedStringKey,
        help: LocalizedStringKey,
        identifier: String,
        action: FindBarAction
    ) -> some View {
        Button(action: { onAction(action) }) {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelIconButtonStyle())
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .focusable(false)
        .disabled(!hasMatches)
        .help(help)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var errorNote: some View {
        if let message = model.errorMessage {
            Text(verbatim: message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .systemRed), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .fixedSize()
                .alignmentGuide(.bottom) { $0[.top] }
                .offset(x: 30, y: 2)
                .allowsHitTesting(false)
                .accessibilityIdentifier("findBar.error")
        }
    }
}

/// 検索のオプションのボタンの見た目。オンのときは文字・背景・枠を強調する。
struct FindOptionToggleStyle: ButtonStyle {
    let isOn: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill(isPressed: configuration.isPressed))
            }
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                }
            }
            .onHover { isHovering = $0 }
    }

    private func fill(isPressed: Bool) -> Color {
        if isOn {
            return Color.accentColor.opacity(isPressed ? 0.28 : 0.18)
        }
        if isPressed { return Color.primary.opacity(0.2) }
        return isHovering ? Color.primary.opacity(0.1) : Color.clear
    }
}
