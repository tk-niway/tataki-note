import Foundation

/// パネルを開くときの挿入先。選んだアプリと、見張りを始めた結果と、待ちの調べ。
struct OpeningTarget {
    /// 選んだアプリ。挿入先を探さないときは nil。
    let app: InsertionTarget?
    /// 開いた時点の挿入先。答えを待つときは nil。
    let target: InsertionTarget?
    /// 開くときの枠を決めるときに、入力欄へ問い合わせてよいか。
    let queriesField: Bool
    /// 開くときの枠を決めるときに使う、フォーカスのある要素の調べの結果。
    let fieldFocus: ObservedFocus?
    /// 答えを待っている調べ。待たないときは nil。
    let pending: Pending?

    /// 答えを待っているときの、調べているアプリ。
    var pendingLookupApp: InsertionTarget? { pending == nil ? nil : app }

    /// 締め切りまでに終わらなかった調べと、その番号。
    struct Pending {
        let lookup: PendingOpeningTargetLookup
        let token: InsertionTargetLookupToken
    }
}

/// パネルを開くときに挿入先を選び、締め切り付きで調べ、見張りを始める。
final class OpeningTargetStarter {
    /// 返した挿入先を、前面のアプリの代わりに挿入先にする。`nil` を返すと前面のアプリを使う。
    var targetOverride: (() -> InsertionTarget?)?
    /// 挿入先を探さず、挿入先が無いものとして開くか。
    var isTargetLookupDisabled = false

    private let targetMonitor: InsertionTargetMonitor
    private let openingLookup: OpeningTargetLookup
    private let exposeWebContent: (InsertionTarget) -> Void
    private let ownProcessIdentifier: pid_t
    private let currentTarget: () -> InsertionTarget?
    private let isOutlineEnabled: () -> Bool
    private let panelScreen: () -> PanelScreen

    init(
        targetMonitor: InsertionTargetMonitor,
        openingLookup: OpeningTargetLookup,
        exposeWebContent: @escaping (InsertionTarget) -> Void,
        ownProcessIdentifier: pid_t,
        currentTarget: @escaping () -> InsertionTarget?,
        isOutlineEnabled: @escaping () -> Bool,
        panelScreen: @escaping () -> PanelScreen
    ) {
        self.targetMonitor = targetMonitor
        self.openingLookup = openingLookup
        self.exposeWebContent = exposeWebContent
        self.ownProcessIdentifier = ownProcessIdentifier
        self.currentTarget = currentTarget
        self.isOutlineEnabled = isOutlineEnabled
        self.panelScreen = panelScreen
    }

    /// 開くときの挿入先のアプリを選ぶ。探さないときは nil。
    func selectApp(looksUpTarget: Bool) -> InsertionTarget? {
        (isTargetLookupDisabled || !looksUpTarget) ? nil : (targetOverride?() ?? currentTarget())
    }

    /// 選んだアプリで見張りを始める。他のアプリなら締め切りまで調べ、終わらなければ答えを待つ。
    func start(app: InsertionTarget?, observedFocus: ObservedFocus?, isTrusted: Bool) -> OpeningTarget {
        let shouldExpose = PanelOpenFrameResolver.shouldExposeWebContent(
            target: app,
            ownProcessIdentifier: ownProcessIdentifier,
            isTrusted: isTrusted
        )
        if let app, targetMonitor.needsOpeningLookup(for: app) {
            let request = OpeningTargetLookupRequest.make(
                app: app,
                observedFocus: observedFocus,
                isOutlineEnabled: isOutlineEnabled(),
                panelScreen: panelScreen(),
                isTrusted: isTrusted,
                shouldExposeWebContent: shouldExpose
            )
            switch openingLookup.lookUp(request, waitingUpTo: OpeningTargetLookupRequest.deadline) {
            case .finished(let result):
                let start = targetMonitor.begin(app: app, lookedUp: result)
                return OpeningTarget(app: app, target: start.target, queriesField: false, fieldFocus: start.focus, pending: nil)
            case .pending(let lookup):
                let token = targetMonitor.beginPending(app: app)
                return OpeningTarget(
                    app: app,
                    target: nil,
                    queriesField: false,
                    fieldFocus: nil,
                    pending: OpeningTarget.Pending(lookup: lookup, token: token)
                )
            }
        }
        if let app, shouldExpose {
            exposeWebContent(app)
        }
        let start = targetMonitor.begin(app: app, observedFocus: observedFocus)
        return OpeningTarget(
            app: app,
            target: start.target,
            queriesField: true,
            fieldFocus: start.focus ?? observedFocus,
            pending: nil
        )
    }

    /// 答えを待っているなら、答えが届いたときに見張りへ渡す。届いていればその場で渡す。
    func deliverPendingAnswer(of opening: OpeningTarget) {
        guard let pending = opening.pending else { return }
        pending.lookup.whenFinished { [weak self, token = pending.token] result in
            self?.targetMonitor.finishPending(token, result: result)
        }
    }
}
