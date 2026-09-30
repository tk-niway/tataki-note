import Observation

/// @note p0-350
enum CommitPlan: Equatable {
    /// @note p0-351
    case dismissOnly
    /// @note p0-352
    case permissionDenied
    /// @note p0-353
    case noTarget
    /// @note p0-354
    case insert(text: String, target: InsertionTarget)
}

/// @note p0-355
@Observable final class PanelModel {
    /// @note p0-356
    var text: String = ""

    private(set) var isPresented = false

    /// @note p0-357
    private(set) var focusRequest = 0

    /// @note p0-358
    private(set) var target: InsertionTarget?

    /// @note p0-359
    @discardableResult func present(target: InsertionTarget?) -> Bool {
        if !isPresented {
            self.target = target
        }
        return present()
    }

    /// @note p0-360
    func prepareCommit(isAccessibilityTrusted: Bool) -> CommitPlan {
        dismiss()
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

    /// @note p0-361
    @discardableResult func restoreDraft(_ draft: String) -> Bool {
        guard text.isEmpty else { return false }
        text = draft
        return true
    }

    /// @note p0-362
    @discardableResult func present() -> Bool {
        let wasPresented = isPresented
        isPresented = true
        focusRequest += 1
        return wasPresented
    }

    /// @note p0-363
    func dismiss() {
        isPresented = false
    }
}
