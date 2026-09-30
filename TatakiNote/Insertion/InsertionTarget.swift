import AppKit

/// @note p0-111
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
}

/// @note p0-112
final class FrontmostAppTracker {
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let ownProcessIdentifier: pid_t
    private var observer: (any NSObjectProtocol)?

    /// @note p0-113
    private(set) var lastActivated: InsertionTarget?

    init(workspace: NSWorkspace = .shared, ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.workspace = workspace
        // @note p0-114
        self.notificationCenter = workspace.notificationCenter
        self.ownProcessIdentifier = ownProcessIdentifier

        if let frontmost = workspace.frontmostApplication, frontmost.processIdentifier != ownProcessIdentifier {
            lastActivated = InsertionTarget(frontmost)
        }

        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.recordActivation(of: app)
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func currentTarget() -> InsertionTarget? {
        Self.chooseTarget(
            frontmost: workspace.frontmostApplication.map { InsertionTarget($0) },
            lastActivated: lastActivated,
            ownProcessIdentifier: ownProcessIdentifier
        )
    }

    /// @note p0-115
    static func chooseTarget(
        frontmost: InsertionTarget?,
        lastActivated: InsertionTarget?,
        ownProcessIdentifier: pid_t
    ) -> InsertionTarget? {
        if let frontmost, frontmost.processIdentifier != ownProcessIdentifier {
            return frontmost
        }
        if let lastActivated, lastActivated.processIdentifier != ownProcessIdentifier {
            return lastActivated
        }
        return nil
    }

    private func recordActivation(of app: NSRunningApplication) {
        guard app.processIdentifier != ownProcessIdentifier else { return }
        lastActivated = InsertionTarget(app)
    }
}
