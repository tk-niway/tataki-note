import Foundation
import Observation

/// 設定画面の「履歴をすべて削除」の状態(押せるか・確認を出しているか)。
@Observable final class HistorySettingsModel {
    @ObservationIgnored private let library: DraftLibrary

    private(set) var isConfirming = false

    init(library: DraftLibrary) {
        self.library = library
    }

    var isClearAvailable: Bool {
        !library.history.isEmpty
    }

    /// 履歴があれば、削除の確認を出す。
    func requestClear() {
        guard isClearAvailable else { return }
        isConfirming = true
    }

    /// 確認を閉じて、履歴をすべて消す。
    func confirmClear() {
        guard isConfirming else { return }
        isConfirming = false
        library.clearHistory()
    }

    /// 履歴を消さずに確認を閉じる。
    func cancelClear() {
        isConfirming = false
    }
}
