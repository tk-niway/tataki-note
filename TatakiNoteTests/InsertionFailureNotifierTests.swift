import Testing
import UserNotifications
@testable import TatakiNote

struct NotificationPostError: Error {}

/// @note p0-878
@MainActor
final class UserNotificationPosterStub: UserNotificationPosting {
    var availabilityValue: NotificationAvailability
    var grantsAuthorization: Bool
    var throwsOnPost: Bool
    private(set) var authorizationRequestCount = 0
    private(set) var posts: [(title: String, body: String, identifier: String)] = []

    init(availability: NotificationAvailability, grantsAuthorization: Bool = false, throwsOnPost: Bool = false) {
        self.availabilityValue = availability
        self.grantsAuthorization = grantsAuthorization
        self.throwsOnPost = throwsOnPost
    }

    func availability() async -> NotificationAvailability {
        availabilityValue
    }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return grantsAuthorization
    }

    func post(title: String, body: String, identifier: String) async throws {
        if throwsOnPost {
            throw NotificationPostError()
        }
        posts.append((title, body, identifier))
    }
}

@MainActor
struct InsertionFailureNotifierTests {
    private let notice = InsertionFailureNotice(reason: .targetNotActivated(appName: "TextEdit"), isDraftKept: true)

    @MainActor
    private final class BeepCounter {
        var count = 0
    }

    private func makeNotifier(poster: UserNotificationPosterStub, beeps: BeepCounter) -> InsertionFailureNotifier {
        InsertionFailureNotifier(poster: poster, beep: { beeps.count += 1 })
    }

    // MARK: - 通知とビープ音の出し分け(AC-21)

    @Test("AC-21: 通知が出せるなら、通知を1回出してビープ音は鳴らさない")
    func availablePostsOnce() async {
        let poster = UserNotificationPosterStub(availability: .available)
        let beeps = BeepCounter()

        await makeNotifier(poster: poster, beeps: beeps).notify(notice)

        #expect(poster.posts.count == 1)
        #expect(poster.posts.first?.identifier == InsertionFailureNotifier.notificationIdentifier)
        #expect(poster.posts.first?.title == notice.title)
        #expect(poster.posts.first?.body == notice.body)
        #expect(poster.authorizationRequestCount == 0)
        #expect(beeps.count == 0)
    }

    @Test("AC-21: 通知が出せないなら、ビープ音を1回鳴らして通知は出さない")
    func unavailableBeepsOnce() async {
        let poster = UserNotificationPosterStub(availability: .unavailable)
        let beeps = BeepCounter()

        await makeNotifier(poster: poster, beeps: beeps).notify(notice)

        #expect(beeps.count == 1)
        #expect(poster.posts.isEmpty)
        #expect(poster.authorizationRequestCount == 0)
    }

    @Test("AC-21: まだ尋ねていなければ許可を1回求め、許可されれば通知を出す")
    func notDeterminedAndGrantedPosts() async {
        let poster = UserNotificationPosterStub(availability: .notDetermined, grantsAuthorization: true)
        let beeps = BeepCounter()

        await makeNotifier(poster: poster, beeps: beeps).notify(notice)

        #expect(poster.authorizationRequestCount == 1)
        #expect(poster.posts.count == 1)
        #expect(beeps.count == 0)
    }

    @Test("AC-21: まだ尋ねていなければ許可を1回求め、許可されなければビープ音を鳴らす")
    func notDeterminedAndDeniedBeeps() async {
        let poster = UserNotificationPosterStub(availability: .notDetermined, grantsAuthorization: false)
        let beeps = BeepCounter()

        await makeNotifier(poster: poster, beeps: beeps).notify(notice)

        #expect(poster.authorizationRequestCount == 1)
        #expect(poster.posts.isEmpty)
        #expect(beeps.count == 1)
    }

    @Test("AC-21: 通知の登録に失敗したら、ビープ音を鳴らす")
    func postFailureBeeps() async {
        let poster = UserNotificationPosterStub(availability: .available, throwsOnPost: true)
        let beeps = BeepCounter()

        await makeNotifier(poster: poster, beeps: beeps).notify(notice)

        #expect(beeps.count == 1)
    }

    @Test("AC-21: 続けて失敗しても、通知は同じ識別子で出す")
    func repeatedFailuresUseSameIdentifier() async {
        let poster = UserNotificationPosterStub(availability: .available)
        let beeps = BeepCounter()
        let notifier = makeNotifier(poster: poster, beeps: beeps)

        await notifier.notify(notice)
        await notifier.notify(InsertionFailureNotice(reason: .noTarget, isDraftKept: true))

        #expect(poster.posts.count == 2)
        #expect(poster.posts.map(\.identifier) == [
            InsertionFailureNotifier.notificationIdentifier,
            InsertionFailureNotifier.notificationIdentifier,
        ])
    }

    @Test("AC-21: 許可の状態から、通知を出せるかを判定する")
    func availabilityFromSettings() {
        let cases: [(UNAuthorizationStatus, UNNotificationSetting, UNAlertStyle, NotificationAvailability, String)] = [
            (.notDetermined, .notSupported, .none, .notDetermined, "notDetermined + notSupported + none"),
            (.authorized, .enabled, .banner, .available, "authorized + enabled + banner"),
            (.authorized, .enabled, .alert, .available, "authorized + enabled + alert"),
            (.authorized, .enabled, .none, .unavailable, "authorized + enabled + none(バナーが出ない)"),
            (.authorized, .disabled, .banner, .unavailable, "authorized + disabled + banner(表示がオフ)"),
            (.authorized, .notSupported, .banner, .unavailable, "authorized + notSupported + banner"),
            (.denied, .enabled, .banner, .unavailable, "denied + enabled + banner"),
            (.provisional, .enabled, .banner, .unavailable, "provisional + enabled + banner(仮の許可)"),
        ]

        for (status, alertSetting, alertStyle, expected, label) in cases {
            let availability = NotificationAvailability(
                authorizationStatus: status,
                alertSetting: alertSetting,
                alertStyle: alertStyle
            )
            #expect(availability == expected, "\(label)")
        }
    }

    // MARK: - 文面(AC-22)

    @Test("AC-22: タイトルは「文章を挿入できませんでした」")
    func titleText() {
        let notices = [
            InsertionFailureNotice(reason: .noTarget, isDraftKept: true),
            InsertionFailureNotice(reason: .targetNotActivated(appName: "TextEdit"), isDraftKept: false),
        ]
        for notice in notices {
            #expect(notice.title == "文章を挿入できませんでした", "\(notice)")
        }
    }

    @Test("AC-22: 本文は、理由(挿入先が分からない・アプリの名前・名前が無ければ「挿入先のアプリ」)と下書きの状態を伝える")
    func bodyText() {
        let noTarget = InsertionFailureNotice(reason: .noTarget, isDraftKept: true).body
        #expect(noTarget.contains("挿入先のアプリが分かりませんでした"))
        #expect(noTarget.contains("下書きとして残っています"))

        let named = InsertionFailureNotice(reason: .targetNotActivated(appName: "TextEdit"), isDraftKept: true).body
        #expect(named.contains("TextEdit"))
        #expect(named.contains("下書きとして残っています"))

        let unnamed = InsertionFailureNotice(reason: .targetNotActivated(appName: nil), isDraftKept: true).body
        #expect(unnamed.contains("挿入先のアプリ"))

        let notKept = InsertionFailureNotice(reason: .targetNotActivated(appName: "TextEdit"), isDraftKept: false).body
        #expect(notKept.contains("TextEdit"))
        #expect(notKept.contains("下書きに戻せませんでした"))
        #expect(!notKept.contains("下書きとして残っています"))
    }

    @Test("入力欄が選ばれていなかったときの本文は、アプリの名前(無ければ「挿入先のアプリ」)と入力欄が選ばれていなかったことを伝える")
    func noTextInputBodyText() {
        let named = InsertionFailureNotice(reason: .noTextInput(appName: "Safari"), isDraftKept: true).body
        #expect(named.contains("Safari"))
        #expect(named.contains("入力欄が選ばれていませんでした"))
        #expect(named.contains("下書きとして残っています"))

        let unnamed = InsertionFailureNotice(reason: .noTextInput(appName: nil), isDraftKept: true).body
        #expect(unnamed.contains("挿入先のアプリ"))
        #expect(unnamed.contains("入力欄が選ばれていませんでした"))
    }
}
