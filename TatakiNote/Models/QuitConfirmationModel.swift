import Foundation
import Observation

/// ⌘Q の確かめの状態。
@Observable final class QuitConfirmationModel {
    private let settings: AppSettings
    private let terminate: () -> Void

    /// 確かめの窓を出しているか。
    private(set) var isConfirming = false
    /// 確かめの窓で、以降の確かめを止めるチェックが付いているか。
    var suppressesFuture = false

    init(settings: AppSettings, terminate: @escaping () -> Void) {
        self.settings = settings
        self.terminate = terminate
    }

    /// ⌘Q を受けて、することを決める。`.confirm` なら確かめ中にしてチェックを外し、`.quit` なら終了する。
    func handleQuitKey(isRecordingShortcut: Bool, isPanelCommitKey: Bool, isModalRunning: Bool) -> QuitKeyAction {
        let action = QuitConfirmation.action(
            isQuitKey: true,
            isRecordingShortcut: isRecordingShortcut,
            isPanelCommitKey: isPanelCommitKey,
            isModalRunning: isModalRunning,
            isConfirming: isConfirming,
            confirmsQuit: settings.confirmsQuit
        )
        switch action {
        case .quit:
            terminate()
        case .confirm:
            isConfirming = true
            suppressesFuture = false
        case .passThrough, .ignore:
            break
        }
        return action
    }

    /// 「終了」。チェックがあれば確かめの設定をオフにしてから終了する。
    func quit() {
        guard isConfirming else { return }
        if suppressesFuture {
            settings.confirmsQuit = false
        }
        isConfirming = false
        terminate()
    }

    /// 「キャンセル」。設定は変えない。
    func cancel() {
        guard isConfirming else { return }
        isConfirming = false
        suppressesFuture = false
    }
}
