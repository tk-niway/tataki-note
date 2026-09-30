import AppKit
import UserNotifications

/// @note p0-92
struct InsertionFailureNotice: Equatable {
    enum Reason: Equatable {
        /// @note p0-93
        case noTarget
        /// @note p0-94
        case targetNotActivated(appName: String?)
        /// @note p0-95
        case noTextInput(appName: String?)
    }

    var reason: Reason
    /// @note p0-96
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
            // @note p0-97
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

/// @note p0-98
enum NotificationAvailability: Equatable {
    case available
    /// @note p0-99
    case notDetermined
    case unavailable

    init(authorizationStatus: UNAuthorizationStatus, alertSetting: UNNotificationSetting, alertStyle: UNAlertStyle) {
        // @note p0-100
        if authorizationStatus == .notDetermined {
            self = .notDetermined
        } else if authorizationStatus == .authorized && alertSetting == .enabled && alertStyle != .none {
            self = .available
        } else {
            // @note p0-101
            self = .unavailable
        }
    }
}

protocol UserNotificationPosting {
    func availability() async -> NotificationAvailability
    func requestAuthorization() async -> Bool
    func post(title: String, body: String, identifier: String) async throws
}

/// @note p0-102
final class InsertionFailureNotifier: InsertionFailureNotifying {
    /// @note p0-103
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
            // @note p0-104
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

/// @note p0-105
final class SystemUserNotificationPoster: NSObject, UserNotificationPosting, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        // @note p0-106
        center.delegate = self
    }

    func availability() async -> NotificationAvailability {
        // @note p0-107
        let settings = await center.notificationSettings()
        return NotificationAvailability(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }

    func requestAuthorization() async -> Bool {
        // @note p0-108
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    func post(title: String, body: String, identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // @note p0-109
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await center.add(request)
    }

    // @note p0-110
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
