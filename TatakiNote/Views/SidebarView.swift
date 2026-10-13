import AppKit
import SwiftUI

/// パネルの左側に出す、下書きと履歴の一覧。
struct SidebarView: View {
    @Bindable var model: SidebarModel
    var glowingDraftID: UUID?
    var onOpenSettings: () -> Void = {}

    @State private var isSearchFocused = false
    @FocusState private var isListFocused: Bool

    private static let rowCornerRadius: CGFloat = 5

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: PanelMetrics.titleBarHeight)
            tabSwitcher
                .padding(.horizontal, 8)
            searchField
                .padding(.top, 6)
                .padding(.horizontal, 8)
            if let message = model.problemMessage {
                problemNote(message)
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            listArea
                .padding(.top, 6)
            footer
        }
        .frame(width: SidebarLayout.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 切り替えと検索

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func tabButton(_ tab: SidebarTab) -> some View {
        let isSelected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Text(verbatim: String(model.count(of: tab)))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityValue("\(model.count(of: tab)) 件")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.tab.\(tab.rawValue)")
    }

    private var searchField: some View {
        SidebarSearchField(
            text: $model.query,
            placeholder: model.tab == .drafts ? "下書きを検索" : "履歴を検索",
            hasPendingFocus: model.hasPendingSearchFocus,
            onFocusHandled: { model.markSearchFocusHandled() },
            onFocusChange: { isSearchFocused = $0 },
            onKey: { key, modifiers, hasMarkedText in
                model.handleKey(key, modifiers: modifiers, hasMarkedText: hasMarkedText || model.markedTextProbe())
            }
        )
        .frame(height: 22)
    }

    private func problemNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(verbatim: message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar.problemMessage")
    }

    // MARK: - 一覧

    @ViewBuilder
    private var listArea: some View {
        let rows = model.rows
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                list(rows)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ rows: [SidebarRow]) -> some View {
        let selection = model.selection
        let isEmphasized = isSearchFocused || isListFocused
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row, isSelected: row.id == selection, isEmphasized: isEmphasized)
                            .id(row.id)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: rows.map(\.id))
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isListFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleListKeyPress(press)
        }
        .accessibilityIdentifier("sidebar.list")
    }

    private func rowView(_ row: SidebarRow, isSelected: Bool, isEmphasized: Bool) -> some View {
        let isHighlighted = isSelected && isEmphasized
        let foreground: Color = isHighlighted ? .white : .primary
        let secondaryForeground: Color = isHighlighted ? .white.opacity(0.85) : .secondary
        return HStack(spacing: 6) {
            if row.kind == .draft {
                Circle()
                    .fill(isHighlighted ? Color.white : Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(row.isShownInPanel ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let detail = row.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                }
                Text(verbatim: row.title)
                    .font(.system(size: 13, weight: row.isShownInPanel ? .medium : .regular))
                    .foregroundStyle(titleStyle(for: row, isHighlighted: isHighlighted, foreground: foreground))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: row.kind == .draft ? 28 : 40)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Self.rowCornerRadius)
                    .fill(rowBackground(isSelected: isSelected, isEmphasized: isEmphasized))
                if row.id == glowingDraftID {
                    SavedRowHighlight(cornerRadius: Self.rowCornerRadius)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.activate(row.id)
        }
        .contextMenu {
            Button("削除") {
                model.requestDelete(row.id)
            }
            .disabled(!model.isDeleteAvailable)
            .accessibilityIdentifier("sidebar.row.deleteMenuItem")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [row.detail, row.title].compactMap { $0 }.joined(separator: " ")))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(row.isShownInPanel ? "パネルに表示中" : "")
        .accessibilityAction(named: "削除") {
            model.requestDelete(row.id)
        }
        .accessibilityIdentifier("sidebar.row")
    }

    private func titleStyle(for row: SidebarRow, isHighlighted: Bool, foreground: Color) -> AnyShapeStyle {
        if row.isUntitled, !isHighlighted {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(foreground)
    }

    private func rowBackground(isSelected: Bool, isEmphasized: Bool) -> Color {
        guard isSelected else { return .clear }
        return isEmphasized ? .accentColor : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isEmptyBySearch ? "magnifyingglass" : model.tab.systemImageName)
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            if let message = model.emptyMessage {
                Text(verbatim: message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar.emptyMessage")
    }

    // MARK: - 下の帯

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onOpenSettings) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                    Text("設定")
                        .font(.system(size: 12))
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelIconButtonStyle())
            .focusable(false)
            .help("設定を開く(⌘,)")
            .accessibilityLabel("設定")
            .accessibilityIdentifier("sidebar.settingsButton")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - キー

    private func handleListKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard let key = Self.sidebarKey(for: press.key) else { return .ignored }
        let handled = model.handleKey(
            key,
            modifiers: Self.modifierFlags(for: press.modifiers),
            hasMarkedText: model.markedTextProbe()
        )
        return handled ? .handled : .ignored
    }

    private static func sidebarKey(for key: KeyEquivalent) -> SidebarKey? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .return: .returnKey
        case .escape: .escape
        case .delete: .deleteBackward
        default: nil
        }
    }

    private static func modifierFlags(for modifiers: EventModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}

private struct SavedRowHighlight: View {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var isFaded = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.yellow.opacity(isFaded ? 0 : (colorScheme == .dark ? 0.25 : 0.45)))
            .onAppear {
                withAnimation(.linear(duration: SaveAnimationModel.arrivalDuration.seconds)) {
                    isFaded = true
                }
            }
            .accessibilityHidden(true)
    }
}
