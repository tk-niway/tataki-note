import AppKit
import Testing
@testable import TatakiNote

@MainActor
final class ActivationRequesterStub: ApplicationActivationRequesting {
    var isRunningResult = true
    var onRequest: (() -> Void)?
    private(set) var requestCount = 0

    func isRunning(_ processIdentifier: pid_t) -> Bool {
        isRunningResult
    }

    func requestActivation(of processIdentifier: pid_t) {
        requestCount += 1
        onRequest?()
    }
}

@MainActor
struct ApplicationActivatorTests {
    private let currentApp = NSRunningApplication.current
    private let unrelatedProcessIdentifier: pid_t = 999_999

    private var currentTarget: InsertionTarget {
        InsertionTarget(processIdentifier: currentApp.processIdentifier)
    }

    private let unreachableTimeout: Duration = .seconds(3600)

    private func postAfterRequest(
        _ name: Notification.Name,
        about app: NSRunningApplication,
        on center: NotificationCenter,
        by requester: ActivationRequesterStub
    ) {
        requester.onRequest = {
            Task { @MainActor in
                center.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
            }
        }
    }

    // MARK: - 前面になった通知で進む

    @Test("AC-8: 前面でないとき前面にする依頼をし、前面になった通知が届いたら上限を待たずに true を返す", .untilStuck)
    func returnsTrueOnActivationNotification() async {
        let center = NotificationCenter()
        let requester = ActivationRequesterStub()
        let frontmost = FrontmostApplicationStub { nil }
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: frontmost,
            notificationCenter: center,
            timeout: unreachableTimeout
        )
        postAfterRequest(NSWorkspace.didActivateApplicationNotification, about: currentApp, on: center, by: requester)

        let result = await activator.activate(currentTarget)

        #expect(result == true)
        #expect(requester.requestCount == 1)
    }

    // MARK: - すでに前面・動いていない

    @Test("AC-9: すでに前面なら依頼をせずに true を返す")
    func returnsTrueWithoutRequestWhenAlreadyFrontmost() async {
        let requester = ActivationRequesterStub()
        let pid = currentApp.processIdentifier
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { pid },
            notificationCenter: NotificationCenter(),
            timeout: .seconds(30)
        )

        let result = await activator.activate(currentTarget)

        #expect(result == true)
        #expect(requester.requestCount == 0)
    }

    @Test("AC-9: 挿入先が動いていなければ依頼をせずに false を返す")
    func returnsFalseWithoutRequestWhenNotRunning() async {
        let requester = ActivationRequesterStub()
        requester.isRunningResult = false
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { nil },
            notificationCenter: NotificationCenter(),
            timeout: .seconds(30)
        )

        let result = await activator.activate(currentTarget)

        #expect(result == false)
        #expect(requester.requestCount == 0)
    }

    // MARK: - 上限・他のアプリの通知

    @Test("AC-10: 上限の時間が過ぎても前面にならなければ false を返す", .untilStuck)
    func returnsFalseAfterTimeout() async {
        let timeout: Duration = .milliseconds(150)
        let requester = ActivationRequesterStub()
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { nil },
            notificationCenter: NotificationCenter(),
            timeout: timeout
        )

        let clock = ContinuousClock()
        let start = clock.now
        let result = await activator.activate(currentTarget)
        let elapsed = clock.now - start

        #expect(result == false)
        #expect(requester.requestCount == 1)
        #expect(elapsed >= timeout)
    }

    @Test("AC-10: 他のアプリが前面になった通知では進まず、上限で false を返す", .untilStuck)
    func ignoresActivationOfOtherApplications() async {
        let timeout: Duration = .milliseconds(300)
        let center = NotificationCenter()
        let requester = ActivationRequesterStub()
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { nil },
            notificationCenter: center,
            timeout: timeout
        )
        let target = InsertionTarget(processIdentifier: unrelatedProcessIdentifier)
        postAfterRequest(NSWorkspace.didActivateApplicationNotification, about: currentApp, on: center, by: requester)

        let clock = ContinuousClock()
        let start = clock.now
        let result = await activator.activate(target)
        let elapsed = clock.now - start

        #expect(result == false)
        #expect(elapsed >= timeout)
    }

    @Test("AC-10: 上限の時点で前面になっていれば、通知が無くても true を返す", .untilStuck)
    func returnsTrueAtTimeoutWhenFrontmostWithoutNotification() async {
        let pid = currentApp.processIdentifier
        let clock = ContinuousClock()
        let start = clock.now
        let activator = WorkspaceApplicationActivator(
            requester: ActivationRequesterStub(),
            frontmostApp: FrontmostApplicationStub { clock.now - start > .milliseconds(50) ? pid : nil },
            notificationCenter: NotificationCenter(),
            timeout: .milliseconds(150)
        )

        let result = await activator.activate(currentTarget)

        #expect(result == true)
    }

    // MARK: - 終了・取り消し

    @Test("AC-11: 待っている間に挿入先が終了した通知が届いたら、上限を待たずに false を返す", .untilStuck)
    func returnsFalseWhenTargetTerminates() async {
        let center = NotificationCenter()
        let requester = ActivationRequesterStub()
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { nil },
            notificationCenter: center,
            timeout: unreachableTimeout
        )
        postAfterRequest(NSWorkspace.didTerminateApplicationNotification, about: currentApp, on: center, by: requester)

        let result = await activator.activate(currentTarget)

        #expect(result == false)
        #expect(requester.requestCount == 1)
    }

    @Test("AC-11: 待っているタスクが取り消されたら false を返す", .untilStuck)
    func returnsFalseWhenCancelled() async {
        let (requested, requestedContinuation) = AsyncStream<Void>.makeStream()
        let requester = ActivationRequesterStub()
        requester.onRequest = { requestedContinuation.finish() }
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { nil },
            notificationCenter: NotificationCenter(),
            timeout: unreachableTimeout
        )
        let target = currentTarget
        let waiting = Task { @MainActor in
            await activator.activate(target)
        }
        for await _ in requested {}

        waiting.cancel()
        let result = await waiting.value

        #expect(result == false)
        #expect(requester.requestCount == 1)
    }

    // MARK: - 依頼の直後の確認・既定の上限

    @Test("AC-12: 依頼の直後に(通知が来る前に)前面になっていたら、通知を待たずに true を返す", .untilStuck)
    func returnsTrueWhenFrontmostRightAfterRequest() async {
        let pid = currentApp.processIdentifier
        var frontmostPid: pid_t?
        let requester = ActivationRequesterStub()
        requester.onRequest = { frontmostPid = pid }
        let activator = WorkspaceApplicationActivator(
            requester: requester,
            frontmostApp: FrontmostApplicationStub { frontmostPid },
            notificationCenter: NotificationCenter(),
            timeout: unreachableTimeout
        )

        let result = await activator.activate(currentTarget)

        #expect(result == true)
        #expect(requester.requestCount == 1)
    }

    @Test("AC-12: 既定の上限は約1秒")
    func defaultTimeoutIsOneSecond() {
        #expect(WorkspaceApplicationActivator().timeout == .seconds(1))
    }
}
