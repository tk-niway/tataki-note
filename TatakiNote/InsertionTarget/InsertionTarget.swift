import AppKit

/// 文章を挿入するアプリ。
struct InsertionTarget: Equatable, Sendable {
    var processIdentifier: pid_t
    var bundleIdentifier: String?
    var localizedName: String?

    init(processIdentifier: pid_t, bundleIdentifier: String? = nil, localizedName: String? = nil) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }

    init(_ app: NSRunningApplication) {
        self.init(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName
        )
    }

    /// 指定したプロセス(自分のアプリ)のものか。
    func isOwnApp(_ ownProcessIdentifier: pid_t) -> Bool {
        processIdentifier == ownProcessIdentifier
    }
}

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
