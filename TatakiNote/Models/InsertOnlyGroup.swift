import Foundation

/// ノートモードでは使わない、設定のまとまり。
enum InsertOnlyGroup: String, CaseIterable {
    case autoShow
    case insertAndSend

    /// ノートモードのときに出す案内の一文。
    var noteModeMessage: String {
        switch self {
        case .autoShow:
            String(localized: "ノートモードでは自動表示しません")
        case .insertAndSend:
            String(localized: "ノートモードでは挿入・送信しません")
        }
    }
}
