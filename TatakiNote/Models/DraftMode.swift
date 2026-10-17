/// 書きかけを挿入できるか(インサート)、挿入・送信しないか(ノート)。
enum DraftMode: String, CaseIterable, Sendable {
    case insert
    case note

    /// もう一方のモード。
    var toggled: DraftMode { self == .insert ? .note : .insert }

    /// 新しい書きかけを始めるモード。チュートリアルを開いている間はインサート。
    static func forNewDraft(setting: DraftMode, isInsertForced: Bool) -> DraftMode {
        isInsertForced ? .insert : setting
    }
}
