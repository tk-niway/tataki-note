import AppKit

/// 確定の結果。
enum CommitOutcome: Equatable {
    case inserted
    case notInserted
}

/// 確定の後、パネルを閉じてから行う処理。
final class CommitPerformer {
    private let model: PanelModel
    private let permission: AccessibilityPermissionChecking
    private let inserter: TextInserting
    private let notifier: InsertionFailureNotifying

    var onPermissionDenied: (() -> Void)?

    init(
        model: PanelModel,
        permission: AccessibilityPermissionChecking,
        inserter: TextInserting,
        notifier: InsertionFailureNotifying
    ) {
        self.model = model
        self.permission = permission
        self.inserter = inserter
        self.notifier = notifier
    }

    @discardableResult
    func perform(_ plan: CommitPlan, shouldSendAfterInsert: Bool = false) async -> CommitOutcome {
        switch plan {
        case .dismissOnly:
            break
        case .permissionDenied:
            if let onPermissionDenied {
                onPermissionDenied()
            } else {
                permission.requestSystemPrompt()
            }
        case .noTarget:
            await notifier.notify(InsertionFailureNotice(reason: .noTarget, isDraftKept: true))
        case .insert(let text, let target):
            let reason: InsertionFailureNotice.Reason
            switch await inserter.insert(text, into: target, shouldSendAfterInsert: shouldSendAfterInsert) {
            case .inserted:
                return .inserted
            case .targetNotActivated:
                reason = .targetNotActivated(appName: target.localizedName)
            case .noTextInput:
                reason = .noTextInput(appName: target.localizedName)
            }
            let isDraftKept = model.restoreDraft(text)
            await notifier.notify(InsertionFailureNotice(reason: reason, isDraftKept: isDraftKept))
        }
        return .notInserted
    }
}
