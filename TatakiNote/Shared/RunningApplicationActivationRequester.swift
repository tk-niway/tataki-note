import AppKit

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
