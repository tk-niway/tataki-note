import SwiftUI

/// @note p0-636
struct PanelStatusBar: View {
    let content: PanelStatusBarContent

    var body: some View {
        // @note p0-637
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.withoutCloseLabel)
            row(.keysOnly)
        }
        // @note p0-638
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(height: PanelMetrics.statusBarHeight)
        .clipped()
        // @note p0-639
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptPanel.statusBar")
    }

    private func row(_ layout: LabelLayout) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(keyEntries) { entry in
                    entryView(entry, layout: layout)
                }
            }
            Spacer(minLength: 14)
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
            KeyHint(key: key, label: label, showsLabel: layout.showsLabel(for: item))
                .accessibilityIdentifier(Self.identifier(for: item))
        case .count(let item, let text):
            Text(verbatim: text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .lineLimit(1)
                // @note p0-640
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

/// @note p0-641
private enum LabelLayout {
    /// @note p0-642
    case full
    /// @note p0-643
    case withoutCloseLabel
    /// @note p0-644
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
}

/// @note p0-645
private struct KeyHint: View {
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
