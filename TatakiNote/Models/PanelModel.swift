import Observation

/// 確定したときに行うこと。
enum CommitPlan: Equatable {
    case emptyText
    case permissionDenied
    case noTarget
    case insert(text: String, target: InsertionTarget)
}

/// パネルの閉じ方。
enum PanelDismissal: Equatable {
    case cancelled
    case committed
}

/// 入力パネルの状態。
@Observable final class PanelModel {
    var text: String = "" {
        didSet {
            if text != oldValue {
                onTextChange?(text)
            }
        }
    }

    /// 本文が変わったときに呼ぶ処理。
    @ObservationIgnored var onTextChange: ((String) -> Void)?

    private(set) var isPresented = false

    /// 最後にパネルを閉じたときの閉じ方。一度も閉じていなければ `nil`。
    private(set) var lastDismissal: PanelDismissal?

    private(set) var focusRequest = 0

    private(set) var target: InsertionTarget?

    @discardableResult func present(target: InsertionTarget?) -> Bool {
        if !isPresented {
            self.target = target
        }
        return present()
    }

    /// 開いている間に挿入先を入れ替える。閉じているとき・変わらないときは何もしない。
    func updateTarget(_ target: InsertionTarget?) {
        guard isPresented, self.target != target else { return }
        self.target = target
    }

    /// 挿入先なしで確定しようとした回数。増えるたびに「挿入先なし」を目立たせる。
    private(set) var noTargetAlertCount = 0

    /// 「挿入先なし」を目立たせる合図を出す。
    func signalNoTarget() {
        noTargetAlertCount += 1
    }

    func prepareCommit(isAccessibilityTrusted: Bool) -> CommitPlan {
        if text.isEmpty {
            return .emptyText
        }
        if !isAccessibilityTrusted {
            dismiss(as: .committed)
            return .permissionDenied
        }
        guard let target else {
            signalNoTarget()
            return .noTarget
        }
        dismiss(as: .committed)
        let committed = text
        text = ""
        return .insert(text: committed, target: target)
    }

    @discardableResult func restoreDraft(_ draft: String) -> Bool {
        guard text.isEmpty else { return false }
        text = draft
        return true
    }

    /// 入力欄へフォーカスを戻すよう求める。
    func requestFocus() {
        focusRequest += 1
    }

    @discardableResult func present() -> Bool {
        let wasPresented = isPresented
        isPresented = true
        focusRequest += 1
        return wasPresented
    }

    func dismiss() {
        dismiss(as: .cancelled)
    }

    private func dismiss(as dismissal: PanelDismissal) {
        if isPresented {
            lastDismissal = dismissal
        }
        isPresented = false
    }
}
