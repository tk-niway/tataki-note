import Foundation
import Observation

/// 設定画面の「履歴」の行の状態(件数・押せるか・確認中か・削除の後か)。
@Observable final class HistorySettingsModel {
    /// 履歴の行の段階。
    enum Phase: Equatable {
        case idle
        case confirming
        case cleared
    }

    @ObservationIgnored private let library: DraftLibrary

    private var storedPhase: Phase = .idle

    /// 削除の直前の件数。
    private(set) var clearedCount = 0
    /// 削除するたびに増える数。
    private(set) var clearedSequence = 0

    init(library: DraftLibrary) {
        self.library = library
    }

    /// 今の段階。削除の後でも履歴が1件以上になっていれば待ちになる。
    var phase: Phase {
        if storedPhase == .cleared, !library.history.isEmpty {
            return .idle
        }
        return storedPhase
    }

    var isConfirming: Bool {
        phase == .confirming
    }

    var historyCount: Int {
        library.history.count
    }

    var isClearAvailable: Bool {
        !library.history.isEmpty
    }

    /// 履歴があれば、削除の確認に移る。
    func requestClear() {
        guard isClearAvailable else { return }
        storedPhase = .confirming
    }

    /// 確認中なら、履歴をすべて消して削除の後に移る。
    func confirmClear() {
        guard isConfirming else { return }
        clearedCount = library.history.count
        library.clearHistory()
        storedPhase = .cleared
        clearedSequence += 1
    }

    /// 確認中なら、履歴を消さずに待ちへ戻す。
    func cancelClear() {
        guard storedPhase == .confirming else { return }
        storedPhase = .idle
    }

    /// 確認中・削除の後を待ちに戻す。履歴には触れない。
    func resetPhase() {
        storedPhase = .idle
    }

    /// 削除する前の件数から、0 までの件数の減り方(最初の件数は含めない)を返す。
    static func countdownSteps(from count: Int) -> [Int] {
        var steps: [Int] = []
        var current = max(count, 0)
        while current > 0 {
            current -= max(1, (current + 5) / 6)
            steps.append(max(current, 0))
        }
        return steps
    }
}
