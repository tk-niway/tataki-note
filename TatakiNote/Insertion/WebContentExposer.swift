import AppKit
import ApplicationServices

/// 起動中のアプリごとに1回だけ、Web の中身をアクセシビリティの仕組みに出すよう頼む。
final class WebContentExposer {
    private let request: (InsertionTarget) -> AXError
    private let notificationCenter: NotificationCenter
    private var terminationObserver: (any NSObjectProtocol)?
    private var exposedProcessIdentifiers: Set<pid_t> = []

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        request: @escaping (InsertionTarget) -> AXError = { AXFocusedTextInputInspector.exposeWebContent(of: $0) }
    ) {
        self.notificationCenter = notificationCenter
        self.request = request
        terminationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app {
                    self?.forget(processIdentifier: app.processIdentifier)
                }
            }
        }
    }

    deinit {
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
    }

    /// まだ頼んでいない(頼んで覚えていない)アプリか。
    func needsRequest(for target: InsertionTarget) -> Bool {
        !exposedProcessIdentifiers.contains(target.processIdentifier)
    }

    /// 頼んだ結果を受け取り、覚えるべき結果なら覚える。
    func record(_ result: AXError, for target: InsertionTarget) {
        if Self.shouldRemember(result) {
            exposedProcessIdentifiers.insert(target.processIdentifier)
        }
    }

    /// まだ頼んでいないアプリなら頼む。
    func expose(_ target: InsertionTarget) {
        guard needsRequest(for: target) else { return }
        record(request(target), for: target)
    }

    /// 終了したアプリを忘れる。
    func forget(processIdentifier: pid_t) {
        exposedProcessIdentifiers.remove(processIdentifier)
    }

    /// 頼んだ結果から、そのアプリを頼み済みとして覚えるか。
    static func shouldRemember(_ result: AXError) -> Bool {
        result == .success || result == .attributeUnsupported
    }
}
