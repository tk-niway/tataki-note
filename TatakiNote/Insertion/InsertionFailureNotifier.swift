import AppKit
import UserNotifications

/// 挿入できなかったことを利用者に伝える内容。
struct InsertionFailureNotice: Equatable {
    enum Reason: Equatable {
        case noTarget
        case targetNotActivated(appName: String?)
        case noTextInput(appName: String?)
    }

    var reason: Reason
    var isDraftKept: Bool

    var title: String {
        String(localized: "文章を挿入できませんでした")
    }

    var body: String {
        reasonSentence + draftSentence
    }

    private var reasonSentence: String {
        switch reason {
        case .noTarget:
            return String(localized: "挿入先のアプリが分かりませんでした。")
        case .targetNotActivated(let appName?):
            return String(localized: "“\(appName)”に挿入できませんでした。")
        case .targetNotActivated(nil):
            return String(localized: "挿入先のアプリに挿入できませんでした。")
        case .noTextInput(let appName?):
            return String(localized: "“\(appName)”で入力欄が選ばれていませんでした。")
        case .noTextInput(nil):
            return String(localized: "挿入先のアプリで入力欄が選ばれていませんでした。")
        }
    }

    private var draftSentence: String {
        if isDraftKept {
            return String(localized: "文章はパネルに下書きとして残っています。")
        }
        return String(localized: "パネルに新しい文章があるため、この文章は下書きに戻せませんでした。")
    }
}

protocol InsertionFailureNotifying {
    func notify(_ notice: InsertionFailureNotice) async
}

/// 通知を出せるか。
enum NotificationAvailability: Equatable {
    case available
    case notDetermined
    case unavailable

    init(authorizationStatus: UNAuthorizationStatus, alertSetting: UNNotificationSetting, alertStyle: UNAlertStyle) {
        if authorizationStatus == .notDetermined {
            self = .notDetermined
        } else if authorizationStatus == .authorized && alertSetting == .enabled && alertStyle != .none {
            self = .available
        } else {
            self = .unavailable
        }
    }
}

protocol UserNotificationPosting {
    func availability() async -> NotificationAvailability
    func requestAuthorization() async -> Bool
    func post(title: String, body: String, identifier: String) async throws
}

/// 挿入できなかったことを通知で伝える。通知が出せないときはビープ音を鳴らす。
final class InsertionFailureNotifier: InsertionFailureNotifying {
    static let notificationIdentifier = "insertionFailed"

    private let poster: UserNotificationPosting
    private let beep: () -> Void

    init(poster: UserNotificationPosting = SystemUserNotificationPoster(), beep: @escaping () -> Void = { NSSound.beep() }) {
        self.poster = poster
        self.beep = beep
    }

    func notify(_ notice: InsertionFailureNotice) async {
        switch await poster.availability() {
        case .unavailable:
            beep()
            return
        case .notDetermined:
            guard await poster.requestAuthorization() else {
                beep()
                return
            }
        case .available:
            break
        }
        do {
            try await poster.post(title: notice.title, body: notice.body, identifier: Self.notificationIdentifier)
        } catch {
            beep()
        }
    }
}

/// 通知センターで通知を出す。
final class SystemUserNotificationPoster: NSObject, UserNotificationPosting, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func availability() async -> NotificationAvailability {
        let settings = await center.notificationSettings()
        return NotificationAvailability(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    func post(title: String, body: String, identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
