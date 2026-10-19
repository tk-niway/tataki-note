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

    /// 上限を縮める確認で待っている上限と、それで消える件数。
    struct PendingHistoryLimit: Equatable {
        let limit: Int
        let removedCount: Int
    }

    @ObservationIgnored private let library: DraftLibrary
    @ObservationIgnored private let settings: AppSettings

    private var storedPhase: Phase = .idle

    /// 削除の直前の件数。
    private(set) var clearedCount = 0
    /// 削除するたびに増える数。
    private(set) var clearedSequence = 0
    /// 上限を縮める確認中なら、その内容。
    private(set) var pendingLimit: PendingHistoryLimit?
    /// 上限の入力欄を今の上限の表示に戻すたびに増える数。
    private(set) var limitFieldResetCount = 0

    init(library: DraftLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    /// 今の履歴の上限。
    var historyLimit: Int {
        library.historyLimit
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
        pendingLimit = nil
        storedPhase = .confirming
    }

    /// 上限を変える。消える履歴が無ければすぐ変え、あれば確認に移る。
    func requestHistoryLimit(_ value: Int) {
        let limit = HistoryLimit.clamped(value)
        guard limit != library.historyLimit else {
            pendingLimit = nil
            return
        }
        let removedCount = library.historyOverflow(forLimit: limit)
        guard removedCount > 0 else {
            pendingLimit = nil
            applyHistoryLimit(limit)
            return
        }
        if storedPhase == .confirming {
            storedPhase = .idle
        }
        pendingLimit = PendingHistoryLimit(limit: limit, removedCount: removedCount)
    }

    /// 確認中なら、その上限に変えて古い履歴を消す。
    func confirmHistoryLimit() {
        guard let pendingLimit else { return }
        applyHistoryLimit(pendingLimit.limit)
        self.pendingLimit = nil
    }

    /// 確認中なら、上限を変えずに確認を閉じ、入力欄を今の上限の表示に戻す。
    func cancelHistoryLimit() {
        pendingLimit = nil
        limitFieldResetCount += 1
    }

    private func applyHistoryLimit(_ limit: Int) {
        settings.historyLimit = limit
        library.setHistoryLimit(limit)
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
        pendingLimit = nil
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
