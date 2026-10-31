import AppKit

/// 確定の結果。
enum CommitOutcome: Equatable {
    case inserted
    case insertedIntoSecureField
    case notInserted
    case notConfirmed
}

extension CommitOutcome {
    /// 挿入できたか。
    var didInsert: Bool { self == .inserted || self == .insertedIntoSecureField }

    /// 挿入した文章を履歴に残すか。
    var recordsHistory: Bool { self == .inserted }
}

/// 確定の後、パネルを閉じてから行う処理。
final class CommitPerformer {
    private let model: PanelModel
    private let permission: AccessibilityPermissionChecking
    private let inserter: TextInserting

    var onPermissionDenied: (() -> Void)?

    init(
        model: PanelModel,
        permission: AccessibilityPermissionChecking,
        inserter: TextInserting
    ) {
        self.model = model
        self.permission = permission
        self.inserter = inserter
    }

    @discardableResult
    func perform(_ plan: CommitPlan, shouldSendAfterInsert: Bool = false) async -> CommitOutcome {
        switch plan {
        case .emptyText:
            break
        case .permissionDenied:
            if let onPermissionDenied {
                onPermissionDenied()
            } else {
                permission.requestSystemPrompt()
            }
        case .noTarget:
            break
        case .insert(let text, let target):
            switch await inserter.insert(text, into: target, shouldSendAfterInsert: shouldSendAfterInsert) {
            case .inserted:
                return .inserted
            case .insertedIntoSecureField:
                return .insertedIntoSecureField
            case .targetNotActivated, .noTextInput:
                model.restoreDraft(text)
            case .pasteNotConfirmed:
                model.restoreDraft(text)
                return .notConfirmed
            }
        }
        return .notInserted
    }
}
