import AppKit
import SwiftUI

/// 検索欄・一覧で受けるキー。
enum SidebarKey: Equatable {
    case up
    case down
    case left
    case right
    case returnKey
    case tab
    case escape
    case deleteBackward
}

/// キーを受けた場所。
enum SidebarKeySource: Equatable {
    case list
    case searchField
}

/// キーに対してサイドバーが行う操作。
enum SidebarKeyAction: Equatable {
    case moveSelection(Int)
    case confirmSelection
    case returnToBody
    case closePanel
    case switchTab
    case deleteSelection
    case swallow
    case passThrough
}

/// 検索欄・一覧のキーを操作に対応づける判定。
enum SidebarKeyResolver {
    /// `⇧Tab` で届くバックタブの文字。
    static let backTab = KeyEquivalent("\u{19}")

    /// 押されたキーに対する操作。
    static func action(
        for key: SidebarKey,
        source: SidebarKeySource,
        modifiers: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> SidebarKeyAction {
        if hasMarkedText { return .passThrough }
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        let isPlain = relevant.isEmpty
        switch key {
        case .up:
            return isPlain ? .moveSelection(-1) : .passThrough
        case .down:
            return isPlain ? .moveSelection(1) : .passThrough
        case .right:
            return isPlain && source == .list ? .confirmSelection : .passThrough
        case .left:
            return isPlain && source == .list ? .swallow : .passThrough
        case .returnKey:
            return isPlain ? .confirmSelection : .swallow
        case .tab:
            guard source == .list, isPlain || relevant == [.shift] else { return .passThrough }
            return .switchTab
        case .escape:
            guard isPlain else { return .passThrough }
            return source == .list ? .closePanel : .returnToBody
        case .deleteBackward:
            return source == .list && relevant == [.command] ? .deleteSelection : .passThrough
        }
    }

    /// SwiftUI のキーを `SidebarKey` にする。バックタブも `.tab`。
    static func key(for equivalent: KeyEquivalent) -> SidebarKey? {
        switch equivalent {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .return: .returnKey
        case .tab, backTab: .tab
        case .escape: .escape
        case .delete: .deleteBackward
        default: nil
        }
    }
}
