import AppKit

enum InsertionResult: Equatable {
    case inserted
    case insertedIntoSecureField
    case targetNotActivated
    case noTextInput
    case pasteNotConfirmed
}

protocol TextInserting {
    func insert(_ text: String, into target: InsertionTarget, shouldSendAfterInsert: Bool) async -> InsertionResult
}

protocol ApplicationActivating {
    func activate(_ target: InsertionTarget) async -> Bool
}

protocol PasteShortcutPosting {
    func postPasteShortcut()
}

/// 挿入先のアプリの状態の確認と、前面にする依頼。
protocol ApplicationActivationRequesting {
    func isRunning(_ processIdentifier: pid_t) -> Bool
    func requestActivation(of processIdentifier: pid_t)
}

struct RunningApplicationActivationRequester: ApplicationActivationRequesting {
    func isRunning(_ processIdentifier: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
        return !app.isTerminated
    }

    func requestActivation(of processIdentifier: pid_t) {
        NSRunningApplication(processIdentifier: processIdentifier)?.activate()
    }
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
        let activated = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notified = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            MainActor.assumeIsolated {
                guard let self, notified == self.pid else { return }
                self.finish(true)
            }
        }
        let terminated = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notified = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            MainActor.assumeIsolated {
                guard let self, notified == self.pid else { return }
                self.finish(false)
            }
        }
        observers = [activated, terminated]

        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            self.finish(self.frontmostApp.frontmostProcessIdentifier == self.pid)
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

struct CGEventPasteShortcutPoster: PasteShortcutPosting {
    private let vKeyCode: CGKeyCode = 9

    func postPasteShortcut() {
        KeyEventPair(keyCode: vKeyCode, flags: .maskCommand)?.post()
    }
}

/// 挿入のための一時的な内容の書き込みに使う、クリップボードの読み書き。
nonisolated protocol InsertionPasteboard: PasteboardAccessing {
    @discardableResult func prepareForNewContents(with options: NSPasteboard.ContentsOptions) -> Int
}

extension NSPasteboard: nonisolated InsertionPasteboard {}

/// クリップボード経由(⌘V の送出)で挿入し、元のクリップボードを全データ型ごと戻す。
final class ClipboardTextInserter: TextInserting {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGeneratedType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    /// ⌘V から、文章が入ったのを確かめるまで待つ時間の上限の既定。
    static let defaultConfirmationTimeout: Duration = .seconds(1)

    private let pasteboard: any InsertionPasteboard
    private let activator: ApplicationActivating
    private let poster: PasteShortcutPosting
    private let focusInspector: FocusedTextInputInspecting
    private let submitSender: SubmitKeySending
    private let submitDelay: Duration
    private let settleDelay: Duration
    private let restoreDelay: Duration
    private let ownProcessIdentifier: pid_t
    private let snapshotter: PasteboardSnapshotting
    private let frontmostApp: FrontmostApplicationReading
    private let confirmationTimeout: Duration
    private let confirmationPollInterval: Duration
    private let maxRecaptures = 3

    private var tail: Task<InsertionResult, Never>?

    init(
        pasteboard: any InsertionPasteboard = NSPasteboard.general,
        activator: ApplicationActivating = WorkspaceApplicationActivator(),
        poster: PasteShortcutPosting = CGEventPasteShortcutPoster(),
        focusInspector: FocusedTextInputInspecting = AXFocusedTextInputInspector(),
        submitSender: SubmitKeySending = EnterKeySender(),
        submitDelay: Duration = .milliseconds(80),
        settleDelay: Duration = .milliseconds(50),
        restoreDelay: Duration = .milliseconds(500),
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        snapshotter: PasteboardSnapshotting? = nil,
        frontmostApp: FrontmostApplicationReading = WorkspaceFrontmostApplication(),
        confirmationTimeout: Duration = ClipboardTextInserter.defaultConfirmationTimeout,
        confirmationPollInterval: Duration = .milliseconds(30)
    ) {
        self.confirmationTimeout = confirmationTimeout
        self.confirmationPollInterval = confirmationPollInterval
        self.pasteboard = pasteboard
        self.activator = activator
        self.poster = poster
        self.focusInspector = focusInspector
        self.submitSender = submitSender
        self.submitDelay = submitDelay
        self.settleDelay = settleDelay
        self.restoreDelay = restoreDelay
        self.ownProcessIdentifier = ownProcessIdentifier
        self.snapshotter = snapshotter ?? BackgroundPasteboardSnapshotter(pasteboard: pasteboard)
        self.frontmostApp = frontmostApp
    }

    func insert(_ text: String, into target: InsertionTarget, shouldSendAfterInsert: Bool) async -> InsertionResult {
        let previous = tail
        let task = Task {
            _ = await previous?.value
            return await self.performInsertion(text, into: target, shouldSendAfterInsert: shouldSendAfterInsert)
        }
        tail = task
        return await task.value
    }

    private func performInsertion(
        _ text: String,
        into target: InsertionTarget,
        shouldSendAfterInsert: Bool
    ) async -> InsertionResult {
        guard await activator.activate(target) else {
            return .targetNotActivated
        }
        let snapshotter = snapshotter
        let capturing = Task { await snapshotter.capture() }
        try? await Task.sleep(for: settleDelay)

        let isOwnTarget = target.isOwnApp(ownProcessIdentifier)
        let inspection = isOwnTarget ? nil : focusInspector.inspectFocusedInput(in: target)
        if let inspection, inspection.state != .textInput {
            _ = await capturing.value
            return .noTextInput
        }
        let confirmation = Self.shouldConfirmPaste(isOwnTarget: isOwnTarget, inspection: inspection)
            ? PasteConfirmation(text: text, valueBefore: focusInspector.focusedTextValue(in: target))
            : nil

        var captured = await capturing.value
        var recaptureCount = 0
        while pasteboard.changeCount != captured.changeCount, recaptureCount < maxRecaptures {
            captured = await snapshotter.capture()
            recaptureCount += 1
        }

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.autoGeneratedType)
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        _ = pasteboard.writeObjects([item])
        let changeCountAfterWrite = pasteboard.changeCount

        guard frontmostApp.frontmostProcessIdentifier == target.processIdentifier else {
            _ = await snapshotter.restore(captured.snapshot, ifChangeCountIs: changeCountAfterWrite)
            return .targetNotActivated
        }
        poster.postPasteShortcut()
        let pastedAt = ContinuousClock.now

        guard let confirmation else {
            if shouldSendAfterInsert {
                try? await Task.sleep(for: submitDelay)
                await submitSender.sendSubmitKey(to: target)
            }

            try? await Task.sleep(for: restoreDelay)

            _ = await snapshotter.restore(captured.snapshot, ifChangeCountIs: changeCountAfterWrite)
            return inspection?.isSecureTextField == true ? .insertedIntoSecureField : .inserted
        }

        let isConfirmed = await waitForPaste(confirmation, in: target, deadline: pastedAt + confirmationTimeout)
        guard isConfirmed else {
            _ = await snapshotter.restore(captured.snapshot, ifChangeCountIs: changeCountAfterWrite)
            return .pasteNotConfirmed
        }
        if shouldSendAfterInsert {
            let earliestSubmit = pastedAt + submitDelay
            if ContinuousClock.now < earliestSubmit {
                try? await Task.sleep(until: earliestSubmit, clock: .continuous)
            }
            await submitSender.sendSubmitKey(to: target)
        }
        try? await Task.sleep(for: restoreDelay)
        _ = await snapshotter.restore(captured.snapshot, ifChangeCountIs: changeCountAfterWrite)
        return .inserted
    }

    /// 貼り付けの後に読んだ入力欄の中身で文章が入ったと言えるか。
    static func shouldConfirmPaste(isOwnTarget: Bool, inspection: FocusedInputInspection?) -> Bool {
        !isOwnTarget && inspection?.state == .textInput && inspection?.isSecureTextField == false
    }

    private func waitForPaste(
        _ confirmation: PasteConfirmation,
        in target: InsertionTarget,
        deadline: ContinuousClock.Instant
    ) async -> Bool {
        while true {
            if confirmation.isConfirmed(by: focusInspector.focusedTextValue(in: target)) {
                return true
            }
            let now = ContinuousClock.now
            if now >= deadline {
                return false
            }
            try? await Task.sleep(for: min(confirmationPollInterval, deadline - now))
        }
    }
}
