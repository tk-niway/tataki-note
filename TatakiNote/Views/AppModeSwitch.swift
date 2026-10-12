import SwiftUI

/// インサート・ノートを切り替える、つまみ付きの2択。
struct AppModeSwitch: View {
    let selection: AppMode
    let onSelect: (AppMode) -> Void

    @Namespace private var thumbNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            segment(.insert, title: "インサート")
            segment(.note, title: "ノート")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .separatorColor).opacity(0.35)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appModeToggle")
    }

    private func segment(_ mode: AppMode, title: LocalizedStringKey) -> some View {
        let isSelected = selection == mode
        return Button {
            select(mode)
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityIdentifier("settings.appMode.\(mode.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ mode: AppMode) {
        if reduceMotion {
            onSelect(mode)
        } else {
            withAnimation(.spring(duration: 0.45)) {
                onSelect(mode)
            }
        }
    }
}
