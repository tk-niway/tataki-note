import ApplicationServices
import Foundation

/// パネルを開くときに、挿入先のアプリへ問い合わせる中身。
nonisolated struct OpeningTargetLookupRequest: Sendable {
    /// 待つ時間の上限。これを超えたら答えを待たずにパネルを出す。
    static let deadline: Duration = .milliseconds(100)

    let app: InsertionTarget
    /// 自動表示の見張りが同じアプリで調べた結果。無ければ問い合わせる。
    let observedProbe: FocusedElementProbe?
    /// 見張りの結果に枠が無いとき、枠を読むか。
    let readsMissingFrame: Bool
    /// 先に Web の中身を出すよう頼むか。
    let shouldExposeWebContent: Bool

    /// 依頼を作る。見張りの結果は、同じアプリのものだけ使う。
    @MainActor
    static func make(
        app: InsertionTarget,
        observedFocus: ObservedFocus?,
        isOutlineEnabled: Bool,
        panelScreen: PanelScreen,
        isTrusted: Bool,
        shouldExposeWebContent: Bool
    ) -> OpeningTargetLookupRequest {
        OpeningTargetLookupRequest(
            app: app,
            observedProbe: observedFocus?.processIdentifier == app.processIdentifier ? observedFocus?.probe : nil,
            readsMissingFrame: isOutlineEnabled || (panelScreen == .nearFocusedField && isTrusted),
            shouldExposeWebContent: shouldExposeWebContent
        )
    }

    /// 見張りの結果に欠けた枠を読むか。
    func needsFrameRead(of probe: FocusedElementProbe) -> Bool {
        readsMissingFrame
            && probe.frame == nil
            && probe.element != nil
            && FocusedTextInputState.classifyForInsertion(probe.lookup, bundleIdentifier: app.bundleIdentifier) == .textInput
    }

    /// 依頼の中身を順に行う。Web の中身の依頼、見張りの結果の利用か問い合わせ、の順。
    func perform(
        now: () -> Date,
        exposeWebContent: () -> Void,
        probeFocusedElement: (InsertionTarget, Bool) -> FocusedElementProbe,
        frame: (AXUIElement) -> CGRect?
    ) -> OpeningTargetLookupResult {
        let start = now()
        if shouldExposeWebContent {
            exposeWebContent()
        }
        let probe: FocusedElementProbe
        let didQuery: Bool
        if let observedProbe {
            if needsFrameRead(of: observedProbe), let element = observedProbe.element {
                probe = FocusedElementProbe(element: element, lookup: observedProbe.lookup, frame: frame(element))
                didQuery = true
            } else {
                probe = observedProbe
                didQuery = false
            }
        } else {
            probe = probeFocusedElement(app, true)
            didQuery = true
        }
        return OpeningTargetLookupResult(probe: probe, didQuery: didQuery, duration: now().timeIntervalSince(start))
    }
}

/// 開くときの調べの結果。
nonisolated struct OpeningTargetLookupResult: Sendable {
    let probe: FocusedElementProbe
    /// AX へ問い合わせたか(見張りの結果をそのまま使ったときは false)。
    let didQuery: Bool
    /// 調べにかかった時間(秒)。
    let duration: TimeInterval
}

/// 調べの終わり方。
enum OpeningTargetLookupOutcome {
    case finished(OpeningTargetLookupResult)
    case pending(PendingOpeningTargetLookup)
}

/// 締め切りまでに終わらなかった調べ。終わったらメインスレッドで知らせる。
final class PendingOpeningTargetLookup {
    private(set) var result: OpeningTargetLookupResult?
    private var handlers: [(OpeningTargetLookupResult) -> Void] = []

    /// 終わったときに呼ぶ処理を登録する。もう終わっていれば、すぐに呼ぶ。
    func whenFinished(_ handler: @escaping (OpeningTargetLookupResult) -> Void) {
        if let result {
            handler(result)
        } else {
            handlers.append(handler)
        }
    }

    /// 調べが終わったことを知らせる。2回目からは何もしない。
    func finish(_ result: OpeningTargetLookupResult) {
        guard self.result == nil else { return }
        self.result = result
        let pendingHandlers = handlers
        handlers = []
        for handler in pendingHandlers {
            handler(result)
        }
    }
}

/// 開くときの挿入先の調べ。
protocol OpeningTargetLookup {
    /// 調べを始め、`deadline` までに終われば `.finished`、終わらなければ `.pending` を返す。
    func lookUp(_ request: OpeningTargetLookupRequest, waitingUpTo deadline: Duration) -> OpeningTargetLookupOutcome
}

/// 調べをメインスレッドの上で行い、いつも `.finished` を返す。
struct SynchronousOpeningTargetLookup: OpeningTargetLookup {
    private let probe: FocusedElementProbing
    private let exposeWebContent: (InsertionTarget) -> Void
    private let now: () -> Date

    init(
        probe: FocusedElementProbing,
        exposeWebContent: @escaping (InsertionTarget) -> Void,
        now: @escaping () -> Date = { Date() }
    ) {
        self.probe = probe
        self.exposeWebContent = exposeWebContent
        self.now = now
    }

    func lookUp(_ request: OpeningTargetLookupRequest, waitingUpTo deadline: Duration) -> OpeningTargetLookupOutcome {
        .finished(
            request.perform(
                now: now,
                exposeWebContent: { exposeWebContent(request.app) },
                probeFocusedElement: { probe.probeFocusedElement(in: $0, readsFrame: $1) },
                frame: { probe.frame(of: $0) }
            )
        )
    }
}
