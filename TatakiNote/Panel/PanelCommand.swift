/// パネルの操作。キーでもボタンでも、`PanelController.perform(_:from:)` に渡す。
enum PanelCommand: Equatable, CaseIterable {
    case close
    case commit
    case commitAndSend
    case openSearch
    case saveDraft
    case newDraft
    case toggleMode
    case switchToInsert
    case toggleSidebar
    case openSettings
    case exportToFile
    case share
}

/// 操作を呼んだところ。
enum PanelCommandSource: Equatable, CaseIterable {
    case key
    case button
}

extension PanelCommand {
    /// 今の書きかけのモードで、この呼び出し元から行うか。
    func isAvailable(in mode: DraftMode, from source: PanelCommandSource) -> Bool {
        switch self {
        case .commit, .commitAndSend:
            switch source {
            case .key: return true
            case .button: return mode == .insert
            }
        case .close, .openSearch, .saveDraft, .newDraft, .toggleMode, .switchToInsert,
             .toggleSidebar, .openSettings, .exportToFile, .share:
            return true
        }
    }

    /// 行う前に、入力欄の変換中の文字を確定するか。
    func commitsMarkedTextFirst(from source: PanelCommandSource) -> Bool {
        switch self {
        case .openSettings:
            return true
        case .close, .commit, .commitAndSend, .saveDraft, .newDraft, .share:
            return source == .button
        case .openSearch, .toggleMode, .switchToInsert, .toggleSidebar, .exportToFile:
            return false
        }
    }

    /// 行った後に、入力欄へフォーカスを戻すよう頼むか。
    func requestsEditorFocusAfterward(from source: PanelCommandSource) -> Bool {
        switch self {
        case .saveDraft:
            return source == .button
        case .close, .commit, .commitAndSend, .openSearch, .newDraft, .toggleMode, .switchToInsert,
             .toggleSidebar, .openSettings, .exportToFile, .share:
            return false
        }
    }
}

extension PanelKeyAction {
    /// キーで選ばれた操作。改行を入れる・通すときは `nil`。
    var command: PanelCommand? {
        switch self {
        case .cancel: return .close
        case .commit: return .commit
        case .commitAndSend: return .commitAndSend
        case .openSearch: return .openSearch
        case .saveDraft: return .saveDraft
        case .newDraft: return .newDraft
        case .toggleMode: return .toggleMode
        case .toggleSidebar: return .toggleSidebar
        case .openSettings: return .openSettings
        case .exportToFile: return .exportToFile
        case .insertNewline, .passThrough: return nil
        }
    }
}

extension PanelStatusItem {
    /// 下の帯でこの項目のボタンを押したときの操作。ボタンでない項目は `nil`。
    var buttonCommand: PanelCommand? {
        switch self {
        case .commit: return .commit
        case .commitAndSend: return .commitAndSend
        case .close, .lineBreak, .characterCount, .lineCount: return nil
        }
    }
}
