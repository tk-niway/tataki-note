import Foundation

/// 確定。挿入先の入力欄を確かめ、パネルを隠して挿入し、挿入できなければパネルを開き直す。
final class PanelCommitFlow {
    /// 確定で挿入することになったとき、パネルを閉じた後・挿入の前に、文章・挿入先・送信もするかを知らせる。
    var onInsertionRequested: ((String, InsertionTarget, Bool) -> Void)?
    /// アクセシビリティの許可が無くて挿入できなかったときに呼ぶ。
    var onPermissionDenied: (() -> Void)? {
        get { performer.onPermissionDenied }
        set { performer.onPermissionDenied = newValue }
    }
    /// 確定する文章が空のときに呼ぶ。
    var onEmptyInput: () -> Void = {}
    /// キー入力をパネルへ戻すときに呼ぶ。
    var onReturnInput: () -> Void = {}
    /// 挿入の前にパネルを隠すときに呼ぶ。
    var onHide: () -> Void = {}
    /// 挿入できなかったときに、パネルを開き直すために呼ぶ。
    var onReopen: () -> Void = {}

    private let model: PanelModel
    private let session: DraftSession
    private let library: DraftLibrary
    private let permission: AccessibilityPermissionChecking
    private let performer: CommitPerformer
    private let targetMonitor: InsertionTargetMonitor
    private let sizing: PanelSizing
    private let ownProcessIdentifier: pid_t

    init(
        model: PanelModel,
        session: DraftSession,
        library: DraftLibrary,
        permission: AccessibilityPermissionChecking,
        inserter: TextInserting,
        targetMonitor: InsertionTargetMonitor,
        sizing: PanelSizing,
        ownProcessIdentifier: pid_t
    ) {
        self.model = model
        self.session = session
        self.library = library
        self.permission = permission
        self.performer = CommitPerformer(model: model, permission: permission, inserter: inserter)
        self.targetMonitor = targetMonitor
        self.sizing = sizing
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    /// 閉じる前に、覚えている入力欄の位置が読めるかを確かめるか。
    static func shouldCheckTrackedField(
        target: InsertionTarget?,
        text: String,
        isTrusted: Bool,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        guard !text.isEmpty, isTrusted, let target else { return false }
        return !target.isOwnApp(ownProcessIdentifier)
    }

    /// 確定する。
    func commit(shouldSendAfterInsert: Bool) {
        library.flush()
        let shouldCheckField = Self.shouldCheckTrackedField(
            target: model.target,
            text: model.text,
            isTrusted: permission.isTrusted,
            ownProcessIdentifier: ownProcessIdentifier
        )
        if shouldCheckField, !targetMonitor.isTrackedFieldReadable() {
            targetMonitor.rejectCurrentField()
            model.signalNoTarget()
            onReturnInput()
            return
        }
        performCommit(shouldSendAfterInsert: shouldSendAfterInsert)
    }

    private func performCommit(shouldSendAfterInsert: Bool) {
        let plan = session.prepareCommit {
            model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        }
        if plan == .noTarget { return }
        if plan == .emptyText {
            onEmptyInput()
            return
        }
        onHide()
        library.flush()
        if case .insert(let text, let target) = plan {
            onInsertionRequested?(text, target, shouldSendAfterInsert)
        }
        Task { [weak self, performer, model] in
            let outcome = await performer.perform(plan, shouldSendAfterInsert: shouldSendAfterInsert)
            self?.sizing.handleCommitOutcome(outcome)
            self?.session.finishCommit(plan, outcome: outcome)
            if case .insert(let text, _) = plan,
               outcome == .notInserted,
               !model.isPresented,
               model.text == text {
                self?.reopenAfterFailedInsertion()
            }
        }
    }

    private func reopenAfterFailedInsertion() {
        onReopen()
        targetMonitor.rejectCurrentField()
        model.signalNoTarget()
    }
}
