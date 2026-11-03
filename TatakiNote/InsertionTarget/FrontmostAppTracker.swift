import AppKit

/// 最前面のアプリと、最後に前面になった自分以外のアプリを覚える。
final class FrontmostAppTracker {
    private let workspace: NSWorkspace
    private let ownProcessIdentifier: pid_t
    private var observer: FrontmostAppObserver?

    private(set) var lastActivated: InsertionTarget?

    init(workspace: NSWorkspace = .shared, ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.workspace = workspace
        self.ownProcessIdentifier = ownProcessIdentifier

        if let frontmost = workspace.frontmostApplication, frontmost.processIdentifier != ownProcessIdentifier {
            lastActivated = InsertionTarget(frontmost)
        }

        observer = FrontmostAppObserver(notificationCenter: workspace.notificationCenter) { [weak self] app in
            guard let app else { return }
            self?.recordActivation(of: app)
        }
    }

    func currentTarget() -> InsertionTarget? {
        Self.chooseTarget(
            frontmost: workspace.frontmostApplication.map { InsertionTarget($0) },
            lastActivated: lastActivated,
            ownProcessIdentifier: ownProcessIdentifier
        )
    }

    static func chooseTarget(
        frontmost: InsertionTarget?,
        lastActivated: InsertionTarget?,
        ownProcessIdentifier: pid_t
    ) -> InsertionTarget? {
        if let frontmost, !frontmost.isOwnApp(ownProcessIdentifier) {
            return frontmost
        }
        if let lastActivated, !lastActivated.isOwnApp(ownProcessIdentifier) {
            return lastActivated
        }
        return nil
    }

    private func recordActivation(of app: NSRunningApplication) {
        guard app.processIdentifier != ownProcessIdentifier else { return }
        lastActivated = InsertionTarget(app)
    }
}
