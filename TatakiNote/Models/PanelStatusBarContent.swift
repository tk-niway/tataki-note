import Foundation

/// パネルの帯に出す、書いた量の数え方。
enum TextStatistics {
    static func characterCount(of text: String) -> Int {
        text.reduce(0) { count, character in
            character.isNewline ? count : count + 1
        }
    }

    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(1) { count, character in
            character.isNewline ? count + 1 : count
        }
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
        entries = items.compactMap { item in
            Self.entry(for: item, text: text, commitKey: commitKey, commitAndSendKey: commitAndSendKey)
        }
    }

    private static func entry(
        for item: PanelStatusItem,
        text: String,
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?
    ) -> Entry? {
        switch item {
        case .lineBreak:
            return .keyHint(item: item, key: "↩", label: String(localized: "改行"))
        case .close:
            return .keyHint(item: item, key: "esc", label: String(localized: "閉じる"))
        case .commit:
            guard let key = commitKey?.displayText else { return nil }
            return .keyHint(item: item, key: key, label: String(localized: "確定+挿入"))
        case .commitAndSend:
            guard let key = commitAndSendKey?.displayText else { return nil }
            return .keyHint(item: item, key: key, label: String(localized: "確定+送信"))
        case .characterCount:
            let count = TextStatistics.characterCount(of: text).formatted()
            return .count(item: item, text: String(localized: "\(count)文字"))
        case .lineCount:
            let count = TextStatistics.lineCount(of: text).formatted()
            return .count(item: item, text: String(localized: "\(count)行"))
        }
    }
}
