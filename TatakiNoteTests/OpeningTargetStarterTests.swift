import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class StarterCalls {
    var exposed: [InsertionTarget] = []
    var overrideCount = 0
    var currentTargetCount = 0
}

@MainActor
private final class StarterFixture {
    static let editor = MonitorFixture.editor
    static let browser = MonitorFixture.browser
    static let own = MonitorFixture.own
    static let focus = FocusedElementProbe(
        element: MonitorFixture.fieldA,
        lookup: MonitorFixture.textField,
        frame: MonitorFixture.frameA
    )

    let model = PanelModel()
    let probe = PerAppProbeStub()
    let lookup: ControlledOpeningTargetLookup
    let monitor: InsertionTargetMonitor
    let starter: OpeningTargetStarter
    let calls = StarterCalls()

    init(
        isOutlineEnabled: Bool = true,
        panelScreen: PanelScreen = .nearFocusedField,
        isRunning: @escaping (pid_t) -> Bool = { _ in true }
    ) {
        probe.results[Self.editor.processIdentifier] = Self.focus
        probe.results[Self.browser.processIdentifier] = FocusedElementProbe(
            element: MonitorFixture.fieldB,
            lookup: MonitorFixture.textField,
            frame: MonitorFixture.frameB
        )
        let lookup = ControlledOpeningTargetLookup(probe: probe)
        let monitor = InsertionTargetMonitor.testFactory(
            probe: probe,
            ownProcessIdentifier: MonitorFixture.ownPid,
            isRunning: isRunning
        )(model)
        let calls = calls
        self.lookup = lookup
        self.monitor = monitor
        self.starter = OpeningTargetStarter(
            targetMonitor: monitor,
            openingLookup: lookup,
            exposeWebContent: { calls.exposed.append($0) },
            ownProcessIdentifier: MonitorFixture.ownPid,
            currentTarget: {
                calls.currentTargetCount += 1
                return Self.browser
            },
            isOutlineEnabled: { isOutlineEnabled },
            panelScreen: { panelScreen }
        )
    }

    func start(
        _ app: InsertionTarget?,
        observedFocus: ObservedFocus? = nil,
        isTrusted: Bool = true
    ) -> OpeningTarget {
        starter.start(app: app, observedFocus: observedFocus, isTrusted: isTrusted)
    }

    func present(_ opening: OpeningTarget) {
        model.present(target: opening.target, pendingLookupApp: opening.pendingLookupApp)
    }

    func close() {
        model.dismiss()
        monitor.end()
    }
}

@MainActor
struct OpeningTargetStarterTests {
    private let editor = StarterFixture.editor
    private let browser = StarterFixture.browser
    private let own = StarterFixture.own

    // MARK: - selectApp

    @Test("AC-1: 差し替えが値を返せばそれを、nil を返せば前面のアプリを選ぶ")
    func selectAppUsesOverrideThenFrontmost() {
        let fixture = StarterFixture()
        let calls = fixture.calls
        fixture.starter.targetOverride = {
            calls.overrideCount += 1
            return MonitorFixture.editor
        }
        #expect(fixture.starter.selectApp(looksUpTarget: true) == editor)
        #expect(calls.overrideCount == 1)
        #expect(calls.currentTargetCount == 0)

        fixture.starter.targetOverride = {
            calls.overrideCount += 1
            return nil
        }
        #expect(fixture.starter.selectApp(looksUpTarget: true) == browser)
        #expect(calls.overrideCount == 2)
        #expect(calls.currentTargetCount == 1)

        fixture.starter.targetOverride = nil
        #expect(fixture.starter.selectApp(looksUpTarget: true) == browser)
        #expect(calls.currentTargetCount == 2)
    }

    @Test("AC-1: 挿入先を探さない設定のときと looksUpTarget が false のときは nil で、差し替えも前面のアプリも読まない")
    func selectAppReturnsNilWithoutReading() {
        let fixture = StarterFixture()
        let calls = fixture.calls
        fixture.starter.targetOverride = {
            calls.overrideCount += 1
            return MonitorFixture.editor
        }

        #expect(fixture.starter.selectApp(looksUpTarget: false) == nil)
        #expect(calls.overrideCount == 0)
        #expect(calls.currentTargetCount == 0)

        fixture.starter.isTargetLookupDisabled = true
        #expect(fixture.starter.selectApp(looksUpTarget: true) == nil)
        #expect(fixture.starter.selectApp(looksUpTarget: false) == nil)
        #expect(calls.overrideCount == 0)
        #expect(calls.currentTargetCount == 0)
    }

    @Test("AC-1: 挿入先を探さない設定の初期値は false")
    func lookupDisabledDefaultsToFalse() {
        let fixture = StarterFixture()
        #expect(!fixture.starter.isTargetLookupDisabled)
        #expect(fixture.starter.selectApp(looksUpTarget: true) == browser)
    }

    // MARK: - start(調べが締め切りまでに終わる)

    @Test("AC-2: 他の動いているアプリで調べが終わると、挿入先・フォーカスの結果が入り、待ちにならない")
    func startFinishedLookup() {
        let fixture = StarterFixture()
        let opening = fixture.start(editor)

        #expect(opening.app == editor)
        #expect(opening.target == editor)
        #expect(opening.pending == nil)
        #expect(opening.pendingLookupApp == nil)
        #expect(!opening.queriesField)
        #expect(opening.fieldFocus?.processIdentifier == editor.processIdentifier)
        #expect(opening.fieldFocus?.probe.frame == MonitorFixture.frameA)
        #expect(!fixture.monitor.isAwaitingOpeningLookup)
        #expect(fixture.lookup.requests.count == 1)
    }

    @Test("AC-2: 調べの依頼に、枠の要否・出す画面・許可・Web の中身を出すかが入る")
    func startPassesRequestValues() {
        let cases: [(isOutlineEnabled: Bool, screen: PanelScreen, isTrusted: Bool, readsFrame: Bool, exposes: Bool)] = [
            (true, .mouse, true, true, true),
            (false, .mouse, true, false, true),
            (false, .nearFocusedField, true, true, true),
            (false, .nearFocusedField, false, false, false),
            (true, .main, false, true, false),
        ]
        for item in cases {
            let fixture = StarterFixture(isOutlineEnabled: item.isOutlineEnabled, panelScreen: item.screen)
            _ = fixture.start(editor, isTrusted: item.isTrusted)

            let request = fixture.lookup.requests.first
            #expect(request?.app == editor)
            #expect(request?.readsMissingFrame == item.readsFrame)
            #expect(request?.shouldExposeWebContent == item.exposes)
        }
    }

    @Test("AC-2: 見張りの結果は、同じアプリのものだけ依頼に渡る")
    func startPassesObservedFocusOnlyForSameApp() {
        let fixture = StarterFixture()
        let sameApp = ObservedFocus(processIdentifier: editor.processIdentifier, probe: StarterFixture.focus)
        _ = fixture.start(editor, observedFocus: sameApp)
        #expect(fixture.lookup.requests.last?.observedProbe != nil)

        fixture.close()
        let otherApp = ObservedFocus(processIdentifier: browser.processIdentifier, probe: StarterFixture.focus)
        _ = fixture.start(editor, observedFocus: otherApp)
        #expect(fixture.lookup.requests.last?.observedProbe == nil)
    }

    @Test("AC-2: Web の中身を出す頼みは自分では行わず、調べの依頼に任せる")
    func startDoesNotExposeWebContentItself() {
        let fixture = StarterFixture()
        _ = fixture.start(editor)
        #expect(fixture.calls.exposed.isEmpty)
        #expect(fixture.lookup.requests.first?.shouldExposeWebContent == true)
    }

    // MARK: - start(調べが締め切りを超える)

    @Test("AC-3: 調べが締め切りを超えると、挿入先は決まらず、調べているアプリと待ちが残る")
    func startPendingLookup() {
        let fixture = StarterFixture()
        fixture.lookup.respondsLate = true
        let opening = fixture.start(editor)

        #expect(opening.target == nil)
        #expect(opening.pending != nil)
        #expect(opening.pendingLookupApp == editor)
        #expect(!opening.queriesField)
        #expect(opening.fieldFocus == nil)
        #expect(fixture.monitor.isAwaitingOpeningLookup)
        #expect(fixture.calls.exposed.isEmpty)

        fixture.present(opening)
        #expect(fixture.model.isTargetPending)
        #expect(fixture.model.target == nil)
        #expect(fixture.model.pendingLookupApp == editor)
    }

    // MARK: - start(調べない)

    @Test("AC-4: 挿入先なしでは調べを使わず、渡した見張りの結果をそのまま返し、Web の中身も頼まない")
    func startWithoutApp() {
        let fixture = StarterFixture()
        let observed = ObservedFocus(processIdentifier: editor.processIdentifier, probe: StarterFixture.focus)
        let opening = fixture.start(nil, observedFocus: observed)

        #expect(opening.app == nil)
        #expect(opening.target == nil)
        #expect(opening.queriesField)
        #expect(opening.pending == nil)
        #expect(opening.fieldFocus?.processIdentifier == editor.processIdentifier)
        #expect(fixture.lookup.requests.isEmpty)
        #expect(fixture.calls.exposed.isEmpty)

        let withoutObserved = StarterFixture().start(nil)
        #expect(withoutObserved.queriesField)
        #expect(withoutObserved.fieldFocus == nil)
    }

    @Test("AC-4: 自分自身では調べを使わず、挿入先は自分自身になり、Web の中身は頼まない")
    func startWithOwnApp() {
        let fixture = StarterFixture()
        let opening = fixture.start(own)

        #expect(opening.target == own)
        #expect(opening.queriesField)
        #expect(opening.pending == nil)
        #expect(fixture.lookup.requests.isEmpty)
        #expect(fixture.calls.exposed.isEmpty)
    }

    @Test("AC-4: 止まったアプリでは調べを使わず、見張りの結果が無ければ渡した見張りの結果を返す")
    func startWithStoppedApp() {
        let fixture = StarterFixture(isRunning: { $0 != StarterFixture.editor.processIdentifier })
        let observed = ObservedFocus(processIdentifier: editor.processIdentifier, probe: StarterFixture.focus)
        let opening = fixture.start(editor, observedFocus: observed)

        #expect(opening.app == editor)
        #expect(opening.target == nil)
        #expect(opening.queriesField)
        #expect(opening.pending == nil)
        #expect(opening.fieldFocus?.processIdentifier == editor.processIdentifier)
        #expect(fixture.lookup.requests.isEmpty)
    }

    @Test("AC-4: 止まったアプリで許可があるときだけ、Web の中身を出す頼みを1回行う")
    func startExposesWebContentOnlyForStoppedAppWithPermission() {
        let isStopped: (pid_t) -> Bool = { $0 != StarterFixture.editor.processIdentifier }

        let trusted = StarterFixture(isRunning: isStopped)
        _ = trusted.start(editor, isTrusted: true)
        #expect(trusted.calls.exposed == [editor])

        let untrusted = StarterFixture(isRunning: isStopped)
        _ = untrusted.start(editor, isTrusted: false)
        #expect(untrusted.calls.exposed.isEmpty)

        let ownApp = StarterFixture()
        _ = ownApp.start(own, isTrusted: true)
        #expect(ownApp.calls.exposed.isEmpty)

        let noApp = StarterFixture()
        _ = noApp.start(nil, isTrusted: true)
        #expect(noApp.calls.exposed.isEmpty)
    }

    // MARK: - deliverPendingAnswer

    @Test("AC-5: 答えが後で届くと、届いたときに挿入先が決まり、待ちの印と調べているアプリが消える")
    func deliverPendingAnswerWhenAnswerArrivesLater() {
        let fixture = StarterFixture()
        fixture.lookup.respondsLate = true
        let opening = fixture.start(editor)
        fixture.present(opening)

        fixture.starter.deliverPendingAnswer(of: opening)
        #expect(fixture.model.isTargetPending)
        #expect(fixture.model.target == nil)
        #expect(fixture.model.pendingLookupApp == editor)

        fixture.lookup.finishAll()
        #expect(fixture.model.target == editor)
        #expect(!fixture.model.isTargetPending)
        #expect(fixture.model.pendingLookupApp == nil)
        #expect(!fixture.monitor.isAwaitingOpeningLookup)
    }

    @Test("AC-5: 答えがもう届いていれば、その場で挿入先が決まり、待ちの印と調べているアプリが消える")
    func deliverPendingAnswerWhenAnswerAlreadyArrived() {
        let fixture = StarterFixture()
        fixture.lookup.respondsLate = true
        let opening = fixture.start(editor)
        fixture.present(opening)
        fixture.lookup.finishAll()
        #expect(fixture.model.isTargetPending)

        fixture.starter.deliverPendingAnswer(of: opening)
        #expect(fixture.model.target == editor)
        #expect(!fixture.model.isTargetPending)
        #expect(fixture.model.pendingLookupApp == nil)
        #expect(!fixture.monitor.isAwaitingOpeningLookup)
    }

    @Test("AC-5: 答えを待っていないときは何もしない")
    func deliverPendingAnswerWithoutPendingDoesNothing() {
        let settled = StarterFixture()
        let opening = settled.start(editor)
        settled.present(opening)
        settled.starter.deliverPendingAnswer(of: opening)
        #expect(settled.model.target == editor)
        #expect(!settled.model.isTargetPending)
        #expect(settled.lookup.requests.count == 1)

        let noApp = StarterFixture()
        let none = noApp.start(nil)
        noApp.present(none)
        noApp.starter.deliverPendingAnswer(of: none)
        #expect(noApp.model.target == nil)
        #expect(!noApp.model.isTargetPending)
        #expect(noApp.model.pendingLookupApp == nil)
    }

    // MARK: - 古い答え

    @Test("AC-6: 答えを待ったまま閉じて開き直した後に前の答えが届いても、挿入先は変わらず待ちのまま。新しい答えだけが反映される")
    func staleAnswerIsDiscardedAfterReopening() {
        let fixture = StarterFixture()
        fixture.lookup.respondsLate = true

        let first = fixture.start(editor)
        fixture.present(first)
        fixture.starter.deliverPendingAnswer(of: first)

        fixture.close()
        let second = fixture.start(browser)
        fixture.present(second)

        fixture.lookup.finishAll()

        #expect(fixture.model.isTargetPending)
        #expect(fixture.model.target == nil)
        #expect(fixture.model.pendingLookupApp == browser)
        #expect(fixture.monitor.isAwaitingOpeningLookup)

        fixture.starter.deliverPendingAnswer(of: second)
        #expect(fixture.model.target == browser)
        #expect(!fixture.model.isTargetPending)
        #expect(fixture.model.pendingLookupApp == nil)
        #expect(!fixture.monitor.isAwaitingOpeningLookup)
    }
}
