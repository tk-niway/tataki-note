import SwiftUI

/// パネルの下の帯。
struct PanelStatusBar: View {
    let content: PanelStatusBarContent
    let onCommit: () -> Void
    let onCommitAndSend: () -> Void

    init(
        content: PanelStatusBarContent,
        onCommit: @escaping () -> Void = {},
        onCommitAndSend: @escaping () -> Void = {}
    ) {
        self.content = content
        self.onCommit = onCommit
        self.onCommitAndSend = onCommitAndSend
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.withoutCloseLabel)
            row(.keysOnly)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: PanelMetrics.statusBarHeight)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptPanel.statusBar")
    }

    private func row(_ layout: LabelLayout) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: layout.itemSpacing) {
                ForEach(keyEntries) { entry in
                    entryView(entry, layout: layout)
                }
            }
            Spacer(minLength: layout.minimumSpacerLength)
            HStack(spacing: 10) {
                ForEach(countEntries) { entry in
                    entryView(entry, layout: layout)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func entryView(_ entry: PanelStatusBarContent.Entry, layout: LabelLayout) -> some View {
        switch entry {
        case .keyHint(let item, let key, let label):
            switch item {
            case .commit:
                StatusKeyButton(
                    key: key,
                    label: label,
                    showsLabel: layout.showsLabel(for: item),
                    horizontalPadding: layout.buttonHorizontalPadding,
                    action: onCommit
                )
                .accessibilityIdentifier(Self.identifier(for: item))
            case .commitAndSend:
                StatusKeyButton(
                    key: key,
                    label: label,
                    showsLabel: layout.showsLabel(for: item),
                    horizontalPadding: layout.buttonHorizontalPadding,
                    action: onCommitAndSend
                )
                .accessibilityIdentifier(Self.identifier(for: item))
            case .close, .lineBreak, .characterCount, .lineCount:
                StatusKeyHint(key: key, label: label, showsLabel: layout.showsLabel(for: item))
                    .accessibilityIdentifier(Self.identifier(for: item))
            }
        case .count(let item, let text):
            Text(verbatim: text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
                .accessibilityIdentifier(Self.identifier(for: item))
        }
    }

    private var keyEntries: [PanelStatusBarContent.Entry] {
        content.entries.filter { entry in
            if case .keyHint = entry { return true }
            return false
        }
    }

    private var countEntries: [PanelStatusBarContent.Entry] {
        content.entries.filter { entry in
            if case .count = entry { return true }
            return false
        }
    }

    private static func identifier(for item: PanelStatusItem) -> String {
        "promptPanel.status.\(item.rawValue)"
    }
}

private enum LabelLayout {
    case full
    case withoutCloseLabel
    case keysOnly

    func showsLabel(for item: PanelStatusItem) -> Bool {
        switch self {
        case .full:
            true
        case .withoutCloseLabel:
            item != .close
        case .keysOnly:
            false
        }
    }

    var itemSpacing: CGFloat {
        self == .keysOnly ? 10 : 14
    }

    var minimumSpacerLength: CGFloat {
        self == .keysOnly ? 8 : 14
    }

    var buttonHorizontalPadding: CGFloat {
        self == .keysOnly ? 3 : 7
    }
}

private struct Keycap: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.22))
                        .offset(y: 1.5)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color(white: 0.29) : Color.white)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .fixedSize()
    }
}

private struct Keycaps: View {
    let key: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(KeycapText.keys(of: key).enumerated()), id: \.offset) { _, part in
                Keycap(text: part)
            }
        }
    }
}

private struct StatusKeyHint: View {
    let key: String
    let label: String
    let showsLabel: Bool

    var body: some View {
        HStack(spacing: 5) {
            Keycaps(key: key)
            if showsLabel {
                Text(verbatim: label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(key) \(label)"))
    }
}

private struct StatusKeyButton: View {
    let key: String
    let label: String
    let showsLabel: Bool
    let horizontalPadding: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Keycaps(key: key)
                if showsLabel {
                    Text(verbatim: label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(StatusKeyButtonStyle())
        .focusable(false)
        .help(Text(verbatim: "\(label)(\(key))"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(key) \(label)"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct StatusKeyButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.24 : (isHovering ? 0.14 : 0)))
            }
            .onHover { isHovering = $0 }
    }
}

/// キーの表記と名前を並べた小さな表示。
struct KeyHint: View {
    let key: String
    let label: String
    let showsLabel: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            if showsLabel {
                Text(verbatim: label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(key) \(label)"))
    }
}
