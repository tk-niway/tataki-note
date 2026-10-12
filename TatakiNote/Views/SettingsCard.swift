import SwiftUI

/// 設定の見出し付きのまとまり(見出し・印・注記・カード・カードの下の説明)。
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    var badge: LocalizedStringKey?
    var note: LocalizedStringKey?
    var footer: String?
    var identifier: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(partIdentifier("title"))
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.17)))
                        .accessibilityIdentifier(partIdentifier("badge"))
                }
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)
            content
            if let footer {
                SettingDescription(footer)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OptionalIdentifier(identifier: identifier))
    }

    private func partIdentifier(_ part: String) -> String {
        identifier.map { "\($0).\(part)" } ?? ""
    }
}

private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// 行を区切り線で並べる、角丸のカード。
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 1) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .separatorColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// カードの1行。左に名前と説明、右に部品を置く。
struct SettingsRow<Accessory: View>: View {
    var title: LocalizedStringKey?
    var description: String?
    var identifier: String?
    @ViewBuilder let accessory: Accessory

    init(
        title: LocalizedStringKey? = nil,
        description: String? = nil,
        identifier: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.description = description
        self.identifier = identifier
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let description {
                        SettingDescription(description)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

extension SettingsRow where Accessory == EmptyView {
    /// 部品の無い行を作る。
    init(title: LocalizedStringKey? = nil, description: String? = nil, identifier: String? = nil) {
        self.init(title: title, description: description, identifier: identifier) { EmptyView() }
    }
}
