/// アプリを終える理由。
enum TerminationReason: Equatable {
    case normal
    case relaunch
}

/// 終了の前に書きかけをどう扱ったか。
enum TerminationOutcome: Equatable {
    case archivedToHistory
    case savedForRelaunch
}
