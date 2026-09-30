/// @note p0-433
enum PanelStatusItem: String, CaseIterable, Sendable {
    /// @note p0-434
    case close
    /// @note p0-435
    case lineBreak
    /// @note p0-436
    case commit
    /// @note p0-437
    case commitAndSend
    /// @note p0-438
    case characterCount
    /// @note p0-439
    case lineCount

    /// @note p0-440
    static func visibleItems(
        hidden: Set<PanelStatusItem>,
        commitKey: PanelShortcut?,
        commitAndSendKey: PanelShortcut?
    ) -> [PanelStatusItem] {
        allCases.filter { item in
            guard !hidden.contains(item) else { return false }
            // @note p0-441
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
