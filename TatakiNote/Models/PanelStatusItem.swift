/// パネルの下の帯に出す項目。
enum PanelStatusItem: String, CaseIterable, Sendable {
    case close
    case lineBreak
    case commit
    case commitAndSend
    case characterCount
    case lineCount

    static func visibleItems(
        hidden: Set<PanelStatusItem>,
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?
    ) -> [PanelStatusItem] {
        allCases.filter { item in
            guard !hidden.contains(item) else { return false }
            switch item {
            case .commit:
                return commitKey != nil
            case .commitAndSend:
                return commitAndSendKey != nil
            case .lineBreak, .close, .characterCount, .lineCount:
                return true
            }
        }
    }
}
