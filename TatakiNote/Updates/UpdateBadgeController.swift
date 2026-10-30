import Foundation

/// 新しい版があるかに合わせて、Dock のアイコンの印を付け外しする。
final class UpdateBadgeController {
    private let updates: UpdateModel
    private let setBadgeLabel: (String?) -> Void
    private var isStarted = false

    init(updates: UpdateModel, setBadgeLabel: @escaping (String?) -> Void) {
        self.updates = updates
        self.setBadgeLabel = setBadgeLabel
    }

    /// 今の状態を当て、新しい版の有無が変わるたびに当て直す。
    func start() {
        guard !isStarted else { return }
        isStarted = true
        reapply()
        observeRepeatedly(
            tracking: { [weak self] in
                _ = self?.updates.isUpdatePending
            },
            onChange: { [weak self] in
                guard let self else { return false }
                self.reapply()
                return true
            }
        )
    }

    /// 今の状態の印を付け直す。
    func reapply() {
        setBadgeLabel(UpdatePresentation.dockBadgeLabel(isUpdatePending: updates.isUpdatePending))
    }
}
