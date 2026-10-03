import Observation

/// 確定したときに、パネルを閉じた後に行うこと。
enum CommitPlan: Equatable {
    case dismissOnly
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
    var text: String = ""

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

    func prepareCommit(isAccessibilityTrusted: Bool) -> CommitPlan {
        dismiss(as: .committed)
        if text.isEmpty {
            return .dismissOnly
        }
        if !isAccessibilityTrusted {
            return .permissionDenied
        }
        guard let target else {
            return .noTarget
        }
        let committed = text
        text = ""
        return .insert(text: committed, target: target)
    }

    @discardableResult func restoreDraft(_ draft: String) -> Bool {
        guard text.isEmpty else { return false }
        text = draft
        return true
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
