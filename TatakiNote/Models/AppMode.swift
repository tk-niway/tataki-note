import Foundation

/// 文章を挿入して使うか、パネルで書くだけで使うか。
enum AppMode: String, CaseIterable, Sendable {
    case insert
    case note
}

/// ノートモードで押せなくする設定の項目。
enum NoteModeRestriction: CaseIterable, Sendable {
    case nearFocusedField
    case insertionTargetOutline

    /// 押せない項目に添える理由の一文。
    var reason: String {
        switch self {
        case .nearFocusedField:
            String(localized: "ノートモードでは選べません。その間は「マウスの近く」に出します。")
        case .insertionTargetOutline:
            String(localized: "ノートモードでは枠線は出ません。")
        }
    }
}
