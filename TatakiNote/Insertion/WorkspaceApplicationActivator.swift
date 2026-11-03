import AppKit

protocol ApplicationActivating {
    func activate(_ target: InsertionTarget) async -> Bool
}

/// 挿入先を前面にし、前面になった通知が届くまで(上限まで)待つ。
struct WorkspaceApplicationActivator: ApplicationActivating {
    let timeout: Duration
    private let requester: ApplicationActivationRequesting
    private let frontmostApp: FrontmostApplicationReading
    private let notificationCenter: NotificationCenter

    init(
        requester: ApplicationActivationRequesting = RunningApplicationActivationRequester(),
        frontmostApp: FrontmostApplicationReading = WorkspaceFrontmostApplication(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        timeout: Duration = .seconds(1)
    ) {
        self.requester = requester
        self.frontmostApp = frontmostApp
        self.notificationCenter = notificationCenter
        self.timeout = timeout
    }

    func activate(_ target: InsertionTarget) async -> Bool {
        let pid = target.processIdentifier
        guard requester.isRunning(pid) else {
            return false
        }
        if frontmostApp.frontmostProcessIdentifier == pid {
            return true
        }

        let waiter = ActivationWaiter(
            pid: pid,
            notificationCenter: notificationCenter,
            frontmostApp: frontmostApp,
            timeout: timeout
        )
        waiter.startObserving()
        requester.requestActivation(of: pid)
        if frontmostApp.frontmostProcessIdentifier == pid {
            waiter.finish(true)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.wait(continuation)
            }
        } onCancel: {
            Task { @MainActor in
                waiter.finish(false)
            }
        }
    }
}

private final class ActivationWaiter {
    private let pid: pid_t
    private let notificationCenter: NotificationCenter
    private let frontmostApp: FrontmostApplicationReading
    private let timeout: Duration
    private var continuation: CheckedContinuation<Bool, Never>?
    private var result: Bool?
    private var isFinished = false
    private var observers: [any NSObjectProtocol] = []
    private var timeoutTask: Task<Void, Never>?

    init(
        pid: pid_t,
        notificationCenter: NotificationCenter,
        frontmostApp: FrontmostApplicationReading,
        timeout: Duration
    ) {
        self.pid = pid
        self.notificationCenter = notificationCenter
        self.frontmostApp = frontmostApp
        self.timeout = timeout
    }

    func startObserving() {
        let activated = observe(NSWorkspace.didActivateApplicationNotification, finishingWith: true)
        let terminated = observe(NSWorkspace.didTerminateApplicationNotification, finishingWith: false)
        observers = [activated, terminated]

        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            self.finish(self.frontmostApp.frontmostProcessIdentifier == self.pid)
        }
    }

    private func observe(_ name: Notification.Name, finishingWith value: Bool) -> any NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            let notified = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            MainActor.assumeIsolated {
                guard let self, notified == self.pid else { return }
                self.finish(value)
            }
        }
    }

    func wait(_ continuation: CheckedContinuation<Bool, Never>) {
        if let result {
            continuation.resume(returning: result)
        } else {
            self.continuation = continuation
        }
    }

    func finish(_ value: Bool) {
        guard !isFinished else { return }
        isFinished = true
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers = []
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: value)
        } else {
            result = value
        }
    }
}
