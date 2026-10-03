import AppKit

/// 前面のアプリが変わるたびに、そのアプリを MainActor で知らせる。破棄すると見張りをやめる。
final class FrontmostAppObserver {
    private let notificationCenter: NotificationCenter
    private var token: (any NSObjectProtocol)?

    init(notificationCenter: NotificationCenter, onActivate: @escaping (NSRunningApplication?) -> Void) {
        self.notificationCenter = notificationCenter
        token = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                onActivate(app)
            }
        }
    }

    deinit {
        if let token {
            notificationCenter.removeObserver(token)
        }
    }
}
