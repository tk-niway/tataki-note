import Foundation

/// パネルの帯に出す、書いた量の数え方。
enum TextStatistics {
    /// 文字数と行数を、文章を1回走査して数える。
    static func counts(of text: String) -> (characters: Int, lines: Int) {
        guard !text.isEmpty else { return (0, 0) }
        var characters = 0
        var newlines = 0
        for character in text {
            if character.isNewline {
                newlines += 1
            } else {
                characters += 1
            }
        }
        return (characters, newlines + 1)
    }

    static func characterCount(of text: String) -> Int {
        counts(of: text).characters
    }

    static func lineCount(of text: String) -> Int {
        counts(of: text).lines
    }
}

/// パネルの帯に出す中身(左からの並び)。
struct PanelStatusBarContent: Equatable {
    enum Entry: Equatable, Identifiable {
        case keyHint(item: PanelStatusItem, key: String, label: String)
        case count(item: PanelStatusItem, text: String)

        var item: PanelStatusItem {
            switch self {
            case .keyHint(let item, _, _), .count(let item, _):
                item
            }
        }

        var id: PanelStatusItem { item }
    }

    let entries: [Entry]

    var isEmpty: Bool { entries.isEmpty }

    init(text: String, items: [PanelStatusItem], commitKey: PanelShortcut?, commitAndSendKey: PanelShortcut?) {
        self.init(
            text: text,
            items: items,
            commitKeyText: commitKey?.displayText,
            commitAndSendKeyText: commitAndSendKey?.displayText
        )
    }

    init(text: String, items: [PanelStatusItem], commitKeyText: String?, commitAndSendKeyText: String?) {
        let needsCounts = items.contains { $0 == .characterCount || $0 == .lineCount }
        let counts = needsCounts ? TextStatistics.counts(of: text) : (characters: 0, lines: 0)
        entries = items.compactMap { item in
            Self.entry(
                for: item,
                counts: counts,
                commitKeyText: commitKeyText,
                commitAndSendKeyText: commitAndSendKeyText
            )
        }
    }

    private static func entry(
        for item: PanelStatusItem,
        counts: (characters: Int, lines: Int),
        commitKeyText: String?,
        commitAndSendKeyText: String?
    ) -> Entry? {
        switch item {
        case .lineBreak:
            return .keyHint(item: item, key: "↩", label: item.displayName)
        case .close:
            return .keyHint(item: item, key: "esc", label: item.displayName)
        case .commit:
            guard let key = commitKeyText else { return nil }
            return .keyHint(item: item, key: key, label: String(localized: "確定+挿入"))
        case .commitAndSend:
            guard let key = commitAndSendKeyText else { return nil }
            return .keyHint(item: item, key: key, label: String(localized: "確定+送信"))
        case .characterCount:
            let count = counts.characters.formatted()
            return .count(item: item, text: String(localized: "\(count)文字"))
        case .lineCount:
            let count = counts.lines.formatted()
            return .count(item: item, text: String(localized: "\(count)行"))
        }
    }
}
