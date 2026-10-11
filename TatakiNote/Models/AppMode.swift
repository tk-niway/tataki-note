import Foundation

/// 文章を挿入して使うか、パネルで書くだけで使うか。
enum AppMode: String, CaseIterable, Sendable {
    case insert
    case note
}

/// ノートモードで押せなくする設定の項目。
enum NoteModeRestriction: CaseIterable, Sendable {
    case nearFocusedField
    case autoShow
    case insertionTargetOutline

    /// 押せない項目に添える理由の一文。
    var reason: String {
        switch self {
        case .nearFocusedField:
            String(localized: "ノートモードでは選べません。「入力欄の近く」を選んでいたときは、ノートモードの間は「マウスの近く」に出し、インサートモードに戻すと「入力欄の近く」に戻ります。")
        case .autoShow:
            String(localized: "ノートモードでは自動表示しません。インサートモードに戻すと、この設定で自動表示します。")
        case .insertionTargetOutline:
            String(localized: "ノートモードでは挿入先を調べないため、枠線は出ません。")
        }
    }
}
