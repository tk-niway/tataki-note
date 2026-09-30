import AppKit

/// @note p0-30
enum CommitOutcome: Equatable {
    /// @note p0-31
    case inserted
    /// @note p0-32
    case notInserted
}

/// @note p0-33
final class CommitPerformer {
    private let model: PanelModel
    private let permission: AccessibilityPermissionChecking
    private let inserter: TextInserting
    private let notifier: InsertionFailureNotifying

    /// @note p0-34
    var onPermissionDenied: (() -> Void)?

    // @note p0-35
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

    /// @note p0-36
    @discardableResult
    func perform(_ plan: CommitPlan, shouldSendAfterInsert: Bool = false) async -> CommitOutcome {
        switch plan {
        case .dismissOnly:
            break
        case .permissionDenied:
            // @note p0-37
            if let onPermissionDenied {
                onPermissionDenied()
            } else {
                permission.requestSystemPrompt()
            }
        case .noTarget:
            // @note p0-38
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
