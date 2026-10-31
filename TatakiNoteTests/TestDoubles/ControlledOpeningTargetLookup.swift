import Foundation
@testable import TatakiNote

/// 開くときの調べを、すぐ終わらせるか、`finishAll()` まで遅らせるかを選べる偽物。
@MainActor
final class ControlledOpeningTargetLookup: OpeningTargetLookup {
    var respondsLate = false
    private(set) var requests: [OpeningTargetLookupRequest] = []
    private let lookup: SynchronousOpeningTargetLookup
    private var held: [(pending: PendingOpeningTargetLookup, result: OpeningTargetLookupResult)] = []

    init(probe: FocusedElementProbing) {
        lookup = SynchronousOpeningTargetLookup(probe: probe, exposeWebContent: { _ in })
    }

    func lookUp(_ request: OpeningTargetLookupRequest, waitingUpTo deadline: Duration) -> OpeningTargetLookupOutcome {
        requests.append(request)
        let outcome = lookup.lookUp(request, waitingUpTo: deadline)
        guard respondsLate, case .finished(let result) = outcome else { return outcome }
        let pending = PendingOpeningTargetLookup()
        held.append((pending, result))
        return .pending(pending)
    }

    func finishAll() {
        let finishing = held
        held = []
        for item in finishing {
            item.pending.finish(item.result)
        }
    }
}
