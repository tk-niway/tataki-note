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
    /// 挿入の結果をパネルで知らせるときに、その文を渡して呼ぶ。
    var onNotice: (String) -> Void = { _ in }

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
            if case .insert(let text, _) = plan {
                let recovery = Self.recovery(for: outcome, isPresented: model.isPresented, isTextRestored: model.text == text)
                switch recovery {
                case .none: break
                case .reopen: self?.reopenAfterFailedInsertion()
                case .rejectTarget: self?.rejectTargetAfterUnconfirmedInsertion()
                }
                if recovery != .none, let message = Self.notice(for: outcome, shouldSendAfterInsert: shouldSendAfterInsert) {
                    self?.onNotice(message)
                }
            }
        }
    }

    private func reopenAfterFailedInsertion() {
        onReopen()
        targetMonitor.rejectCurrentField()
        model.signalNoTarget()
    }

    private func rejectTargetAfterUnconfirmedInsertion() {
        targetMonitor.rejectCurrentField()
        model.signalNoTarget()
    }

    /// 確定+送信で文章が入ったのを確かめられなかったときの文。
    static let notConfirmedSentMessage = String(localized: "送信できませんでした")
    /// 確定+挿入で文章が入ったのを確かめられなかったときの文。
    static let notConfirmedInsertedMessage = String(localized: "挿入できませんでした")

    /// 挿入の結果に応じて、パネルで知らせる文。知らせないなら nil。
    static func notice(for outcome: CommitOutcome, shouldSendAfterInsert: Bool) -> String? {
        guard outcome == .notConfirmed else { return nil }
        return shouldSendAfterInsert ? notConfirmedSentMessage : notConfirmedInsertedMessage
    }

    /// 確定の後に、パネルをどう戻すか。
    enum FailureRecovery: Equatable {
        case none
        case reopen
        case rejectTarget
    }

    /// 確定の結果・パネルが開いているか・確定した文章が本文に戻ったかから、パネルの戻し方を決める。
    static func recovery(for outcome: CommitOutcome, isPresented: Bool, isTextRestored: Bool) -> FailureRecovery {
        guard isTextRestored else { return .none }
        switch outcome {
        case .inserted, .insertedIntoSecureField:
            return .none
        case .notInserted:
            return isPresented ? .none : .reopen
        case .notConfirmed:
            return isPresented ? .rejectTarget : .reopen
        }
    }
}
