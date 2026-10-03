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

    /// まだ頼んでいないアプリなら頼む。
    func expose(_ target: InsertionTarget) {
        guard !exposedProcessIdentifiers.contains(target.processIdentifier) else { return }
        if Self.shouldRemember(request(target)) {
            exposedProcessIdentifiers.insert(target.processIdentifier)
        }
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
