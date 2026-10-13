import SwiftUI

/// ノートモードのとき、中身を薄くして押せなくし、案内の帯を上に出す。
struct InsertOnlyGate<Content: View>: View {
    let group: InsertOnlyGroup
    let isNoteMode: Bool
    let onSwitchToInsert: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isNoteMode {
                banner
            }
            content
                .disabled(isNoteMode)
                .opacity(isNoteMode ? 0.4 : 1)
                .saturation(isNoteMode ? 0 : 1)
        }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Text(group.noteModeMessage)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("インサートに切り替える →", action: onSwitchToInsert)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("settings.noteModeBanner.\(group.rawValue).switchToInsert")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.noteModeBanner.\(group.rawValue)")
    }
}
