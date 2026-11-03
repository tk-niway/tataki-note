import AppKit

/// 文章を挿入するアプリ。
nonisolated struct InsertionTarget: Equatable, Sendable {
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
