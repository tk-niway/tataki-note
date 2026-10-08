import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class MonitorEnvironment {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    var stoppedProcesses: Set<pid_t> = []
    var frontmost: InsertionTarget?
    var windows: [OnScreenWindow] = []
    var windowListCalls = 0
    var mouse = CGPoint.zero
    var exposed: [InsertionTarget] = []
    var isOutlineEnabled = true
    var isOwnTargetAvailable = true
    var adoptedCount = 0
}

@MainActor
final class MonitorFixture {
    static let ownPid: pid_t = 4242
    static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let editor = InsertionTarget(processIdentifier: 5001, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
    static let browser = InsertionTarget(processIdentifier: 5002, bundleIdentifier: "com.example.Browser", localizedName: "Browser")
    static let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    static let fieldA = AXUIElementCreateApplication(7001)
    static let fieldB = AXUIElementCreateApplication(7002)
    static let frameA = CGRect(x: 100, y: 100, width: 300, height: 40)
    static let frameB = CGRect(x: 100, y: 200, width: 300, height: 40)
    static let textField = FocusedElementLookup.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: true)
    static let secureTextField = FocusedElementLookup.element(
        role: "AXTextField", subrole: "AXSecureTextField", isSelectedTextRangeSettable: true
    )
    static let button = FocusedElementLookup.element(role: "AXButton", subrole: nil, isSelectedTextRangeSettable: false)
    static let unknownGroup = FocusedElementLookup.element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: false)

    let env = MonitorEnvironment()
    let model = PanelModel()
    let probe = PerAppProbeStub()
    let clicks = ClickMonitorStub()
    let monitor: InsertionTargetMonitor

    init(polls: Bool = false) {
        let env = env
        let probe = probe
        let clicks = clicks
        env.windows = [Self.window(of: Self.editor)]
        let sleep: (Duration) async -> Void = polls ? { _ in await Task.yield() } : { _ in }
        let monitor = InsertionTargetMonitor(
            panelModel: model,
            probe: probe,
            ownProcessIdentifier: Self.ownPid,
            exposeWebContent: { env.exposed.append($0) },
            isOutlineEnabled: { env.isOutlineEnabled },
            frontmostApplication: { env.frontmost },
            isRunning: { !env.stoppedProcesses.contains($0) },
            onScreenWindows: {
                env.windowListCalls += 1
                return env.windows
            },
            mouseLocation: { env.mouse },
            primaryScreenFrame: { MonitorFixture.screen },
            now: { env.now },
            sleep: sleep,
            pollsAutomatically: polls,
            addClickMonitor: { clicks.add($0) },
            removeClickMonitor: { clicks.remove($0) }
        )
        monitor.isOwnTargetAvailable = { env.isOwnTargetAvailable }
        monitor.onFieldAdopted = { env.adoptedCount += 1 }
        self.monitor = monitor
    }

    static func window(of target: InsertionTarget) -> OnScreenWindow {
        OnScreenWindow(processIdentifier: target.processIdentifier, layer: 0, bounds: screen)
    }

    func focus(
        _ element: AXUIElement?,
        frame: CGRect?,
        lookup: FocusedElementLookup = MonitorFixture.textField,
        in target: InsertionTarget
    ) {
        probe.results[target.processIdentifier] = FocusedElementProbe(element: element, lookup: lookup, frame: frame)
    }

    @discardableResult
    func open(_ app: InsertionTarget?, observedFocus: ObservedFocus? = nil) -> InsertionTargetStart {
        let start = monitor.begin(app: app, observedFocus: observedFocus)
        model.present(target: start.target)
        return start
    }

    func clickPoint(inside frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: Self.screen.maxY - frame.midY)
    }

    func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
struct InsertionTargetMonitorTests {
    private typealias Fixture = MonitorFixture

    // MARK: - AC-5 開いた時点の挿入先

    @Test(
        "AC-5: 開いた時点でフォーカスのある要素が入力欄(パスワード欄を含む)なら挿入先はそのアプリ、でなければ挿入先なし",
        arguments: [
            (Fixture.textField, true),
            (Fixture.secureTextField, true),
            (Fixture.button, false),
            (Fixture.unknownGroup, false),
            (FocusedElementLookup.noFocusedElement, false),
            (FocusedElementLookup.unavailable, false),
        ]
    )
    func targetAtOpenFollowsFocusedElement(lookup: FocusedElementLookup, isTarget: Bool) {
        let f = Fixture()
        let hasElement = lookup != .noFocusedElement && lookup != .unavailable
        f.focus(hasElement ? Fixture.fieldA : nil, frame: Fixture.frameA, lookup: lookup, in: Fixture.editor)

        let start = f.open(Fixture.editor)

        #expect(start.target == (isTarget ? Fixture.editor : nil))
        #expect(f.model.target == (isTarget ? Fixture.editor : nil))
    }

    @Test("AC-5: アプリが決まらないときは挿入先なしで、問い合わせない")
    func noAppMeansNoTarget() {
        let f = Fixture()

        let start = f.open(nil)

        #expect(start.target == nil)
        #expect(start.focus == nil)
        #expect(f.model.target == nil)
        #expect(f.probe.targets.isEmpty)
    }

    @Test("AC-5: 入力欄のときは枠を返し、使った調べの結果を返す")
    func beginReturnsOutlineAndUsedFocus() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)

        let start = f.open(Fixture.editor)

        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(start.focus?.processIdentifier == Fixture.editor.processIdentifier)
        #expect(start.focus?.probe.frame == Fixture.frameA)
        #expect(f.probe.targets == [Fixture.editor])
        #expect(f.probe.readsFrameValues == [true])
    }

    @Test("AC-5: 同じアプリの自動表示の結果があれば問い合わせずに使い、別のアプリの結果は使わない")
    func observedFocusIsUsedWithoutQuerying() {
        let f = Fixture()
        let observed = ObservedFocus(
            processIdentifier: Fixture.editor.processIdentifier,
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.textField, frame: Fixture.frameA)
        )

        let start = f.open(Fixture.editor, observedFocus: observed)

        #expect(start.target == Fixture.editor)
        #expect(f.probe.targets.isEmpty)
        #expect(f.monitor.outline.rect == Fixture.frameA)

        let g = Fixture()
        g.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        let foreign = ObservedFocus(
            processIdentifier: Fixture.browser.processIdentifier,
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.textField, frame: Fixture.frameA)
        )

        let second = g.open(Fixture.editor, observedFocus: foreign)

        #expect(g.probe.targets == [Fixture.editor])
        #expect(second.focus?.probe.frame == Fixture.frameB)
    }

    @Test("AC-5: 自動表示の結果に枠が無く入力欄なら、要素の枠を1回だけ読み足す")
    func observedFocusWithoutFrameReadsElementFrameOnce() {
        let f = Fixture()
        f.probe.elementFrame = Fixture.frameA
        let observed = ObservedFocus(
            processIdentifier: Fixture.editor.processIdentifier,
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.textField, frame: nil)
        )

        let start = f.open(Fixture.editor, observedFocus: observed)

        #expect(f.probe.targets.isEmpty)
        #expect(f.probe.frameRequests.count == 1)
        #expect(start.focus?.probe.frame == Fixture.frameA)
        #expect(f.monitor.outline.rect == Fixture.frameA)
    }

    @Test("AC-5: 自動表示の結果が入力欄でないなら問い合わせず、枠も読まず、挿入先なし")
    func observedNonTextInputDoesNotQuery() {
        let f = Fixture()
        let observed = ObservedFocus(
            processIdentifier: Fixture.editor.processIdentifier,
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.button, frame: nil)
        )

        let start = f.open(Fixture.editor, observedFocus: observed)

        #expect(start.target == nil)
        #expect(f.probe.targets.isEmpty)
        #expect(f.probe.frameRequests.isEmpty)
    }

    // MARK: - AC-6 開いている間の移動

    @Test("AC-6: フォーカスが別の入力欄へ移ると挿入先と枠が移り、入力欄でない所では挿入先なし、戻ると戻る")
    func followsFocusAcrossFields() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameB)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, lookup: Fixture.button, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
    }

    @Test("AC-6: 入力欄が無い状態で開いても、あとで入力欄が選ばれると挿入先になる")
    func becomesTargetWhenFieldAppearsLater() {
        let f = Fixture()
        f.open(Fixture.editor)
        #expect(f.model.target == nil)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.monitor.refresh()

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
    }

    @Test("AC-6: 定期の調べが自動で動き、パネルを閉じると止まる")
    func pollingRunsUntilDismissed() async {
        let f = Fixture(polls: true)
        f.open(Fixture.editor)
        #expect(f.model.target == nil)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        await f.settle()
        #expect(f.model.target == Fixture.editor)

        f.model.dismiss()
        await f.settle()
        let probesAfterDismiss = f.probe.targets.count
        await f.settle()
        #expect(f.probe.targets.count == probesAfterDismiss)
    }

    // MARK: - AC-7 アプリの終了

    @Test("AC-7: 挿入先のアプリが終了すると挿入先なしになり、以後そのアプリを調べない")
    func terminatedAppStopsBeingQueried() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        let probesBefore = f.probe.targets.count

        f.env.stoppedProcesses.insert(Fixture.editor.processIdentifier)
        f.monitor.refresh()

        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.probe.targets.count == probesBefore)

        f.env.stoppedProcesses.removeAll()
        f.monitor.refresh()
        f.monitor.refresh()
        #expect(f.model.target == nil)
        #expect(f.probe.targets.count == probesBefore)
    }

    // MARK: - AC-8 クリックでの選び直し

    @Test("AC-8: 他のアプリの入力欄の中をクリックすると、そのアプリのその入力欄が挿入先になり、Web の中身を出す頼みが1回行われる")
    func clickInsideOtherAppsFieldAdoptsIt() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.windows = [Fixture.window(of: Fixture.browser), Fixture.window(of: Fixture.editor)]
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.browser)
        #expect(f.monitor.outline.rect == Fixture.frameB)
        #expect(f.env.exposed == [Fixture.browser])
        #expect(f.env.adoptedCount == 1)

        f.monitor.refresh()
        #expect(f.model.target == Fixture.browser)
    }

    @Test("AC-8: 同じアプリの別の入力欄をクリックしたときは、Web の中身を出す頼みをしない")
    func clickInsideSameAppsFieldDoesNotExposeAgain() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.env.frontmost = Fixture.editor
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameB)
        #expect(f.env.exposed.isEmpty)
        #expect(f.env.adoptedCount == 1)
    }

    @Test("AC-8: 枠が読めない入力欄は、クリックの位置を確かめずに選ぶ")
    func fieldWithoutFrameIsAdoptedWithoutCheckingPoint() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: nil, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = CGPoint(x: 900, y: 10)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.browser)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.env.adoptedCount == 1)
    }

    @Test("AC-8: 入力欄以外のクリックでは、挿入先も選び直しの知らせも変わらない")
    func clickOnNonInputKeepsTarget() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, lookup: Fixture.button, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.editor)
        #expect(f.env.adoptedCount == 0)
        #expect(f.env.exposed.isEmpty)
    }

    @Test("AC-8: 入力欄の枠の外(タイトルバーなど)のクリックでは移らない")
    func clickOutsideFieldFrameKeepsTarget() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameA)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.editor)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-8: 自分のウィンドウのクリックでは移らず、前面のアプリを調べない")
    func clickInOwnWindowKeepsTarget() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        let probesBefore = f.probe.targets.count
        f.env.frontmost = Fixture.own

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.editor)
        #expect(f.probe.targets.count == probesBefore)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-8: クリックの無い前面のアプリの切り替えでは、挿入先は変わらない")
    func activationWithoutClickKeepsTarget() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)

        f.env.frontmost = Fixture.browser
        f.monitor.refresh()

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-8: 挿入先のアプリの入力欄でない所をクリックすると、挿入先なしになる")
    func clickOnNonInputInTargetAppClearsTarget() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, lookup: Fixture.button, in: Fixture.editor)
        f.env.frontmost = Fixture.editor
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-8: 最初に入力欄と分からなくても、少し後の調べ直しで入力欄なら挿入先になり、知らせは1回")
    func recheckAdoptsFieldThatAppearsLate() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(nil, frame: nil, lookup: .noFocusedElement, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        #expect(f.model.target == Fixture.editor)
        #expect(f.env.adoptedCount == 0)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        await f.settle()

        #expect(f.model.target == Fixture.browser)
        #expect(f.env.exposed == [Fixture.browser])
        #expect(f.env.adoptedCount == 1)
    }

    @Test("AC-8: 調べ直しでも入力欄でなければ、選び直しの知らせは出ない")
    func recheckThatFindsNothingDoesNotNotify() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, lookup: Fixture.button, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)
        let probesBefore = f.probe.probeCount(for: Fixture.browser)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.probe.probeCount(for: Fixture.browser) == probesBefore + 2)
        #expect(f.model.target == Fixture.editor)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-8: すぐ選んだときは、調べ直しは行われず知らせは1回")
    func immediateAdoptionSkipsRecheck() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.probe.probeCount(for: Fixture.browser) == 2)
        #expect(f.env.adoptedCount == 1)
    }

    @Test("AC-8: 全体のクリックの見張りが張られ、そのクリックで選び直しが行われる")
    func globalClickMonitorTriggersAdoption() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.clicks.activeCount == 1)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.clicks.fire()
        await f.settle()

        #expect(f.model.target == Fixture.browser)
    }

    // MARK: - AC-9 TatakiNote 自身

    @Test("AC-9: 自分自身が挿入先のときは問い合わせず挿入先のまま(枠は無し)で、チュートリアルの窓が見えなくなると挿入先なし")
    func ownAppTargetIsNotQueried() {
        let f = Fixture()

        let start = f.open(Fixture.own)

        #expect(start.target == Fixture.own)
        #expect(f.model.target == Fixture.own)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.probe.targets.isEmpty)

        f.monitor.refresh()
        #expect(f.model.target == Fixture.own)

        f.env.isOwnTargetAvailable = false
        f.monitor.refresh()
        #expect(f.model.target == nil)

        f.env.isOwnTargetAvailable = true
        f.monitor.refresh()
        #expect(f.model.target == Fixture.own)
        #expect(f.probe.targets.isEmpty)
    }

    @Test("AC-9: 開く時点で練習用のチャットが使えないなら挿入先なし")
    func unavailableOwnTargetAtOpen() {
        let f = Fixture()
        f.env.isOwnTargetAvailable = false

        let start = f.open(Fixture.own)

        #expect(start.target == nil)
        #expect(f.probe.targets.isEmpty)
    }

    // MARK: - AC-10 パネルを閉じる

    @Test("AC-10: パネルを閉じると見張りが止まって枠が消え、その後の調べ直し・クリックでは何も変わらない")
    func dismissalStopsMonitoring() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.clicks.activeCount == 1)

        f.model.dismiss()
        await f.settle()

        #expect(f.monitor.outline.rect == nil)
        #expect(f.clicks.activeCount == 0)

        let probesBefore = f.probe.targets.count
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)
        f.monitor.refresh()
        f.monitor.handleClick()
        await f.settle()

        #expect(f.probe.targets.count == probesBefore)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.env.adoptedCount == 0)
    }

    @Test("AC-10: 確定で閉じたときも見張りが止まる")
    func commitStopsMonitoring() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        _ = f.model.prepareCommit(isAccessibilityTrusted: true)
        await f.settle()

        #expect(f.monitor.outline.rect == nil)
        #expect(f.clicks.activeCount == 0)
    }

    @Test("AC-10: 閉じてすぐ開き直したときは、見張りを止めない")
    func reopeningKeepsMonitoring() async {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.model.dismiss()
        f.open(Fixture.editor)
        await f.settle()

        #expect(f.monitor.outline.rect == Fixture.frameA)
        #expect(f.clicks.activeCount == 1)
    }

    @Test("AC-10: 見張りをやめると、クリックの見張りは外れ、枠が消える")
    func endRemovesClickMonitorAndOutline() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.monitor.end()

        #expect(f.monitor.outline.rect == nil)
        #expect(f.clicks.removed == 1)
        #expect(f.clicks.activeCount == 0)
    }

    // MARK: - AC-19 答えないアプリ

    @Test("AC-19: 挿入先のアプリが答えないと挿入先なしになり、1秒間は問い合わせず、1秒たつと調べ直す")
    func unavailableAppBacksOffForOneSecond() {
        let f = Fixture()
        f.focus(nil, frame: nil, lookup: .unavailable, in: Fixture.editor)

        f.open(Fixture.editor)
        #expect(f.model.target == nil)
        #expect(f.probe.targets.count == 1)

        f.env.now += 0.5
        f.monitor.refresh()
        #expect(f.probe.targets.count == 1)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.env.now += 0.4
        f.monitor.refresh()
        #expect(f.probe.targets.count == 1)
        #expect(f.model.target == nil)

        f.env.now += 0.6
        f.monitor.refresh()
        #expect(f.probe.targets.count == 2)
        #expect(f.model.target == Fixture.editor)
    }

    @Test("AC-19: 開く時点で答えなかったときも、1秒間は問い合わせない")
    func unavailableAtOpenBacksOff() {
        let f = Fixture()
        f.focus(nil, frame: nil, lookup: .unavailable, in: Fixture.editor)

        let start = f.open(Fixture.editor)

        #expect(start.target == nil)
        #expect(start.focus?.probe.lookup == .unavailable)
        f.monitor.refresh()
        f.monitor.refresh()
        #expect(f.probe.targets.count == 1)
    }

    // MARK: - AC-26 時間の歯止め

    @Test("AC-26: 1回の調べに 30ms を超えると 0.5 秒は定期の調べで問い合わせず、前のままで、0.5 秒たつと調べ直す")
    func slowQueryDelaysNextPoll() {
        let f = Fixture()
        f.probe.onProbe = { f.env.now += 0.05 }
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.probe.targets.count == 1)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.probe.targets.count == 1)
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameA)

        f.env.now += 0.4
        f.monitor.refresh()
        #expect(f.probe.targets.count == 1)

        f.env.now += 0.2
        f.monitor.refresh()
        #expect(f.probe.targets.count == 2)
        #expect(f.monitor.outline.rect == Fixture.frameB)
    }

    @Test("AC-26: 30ms 以内の調べなら、定期の調べは遅れない")
    func fastQueryDoesNotDelay() {
        let f = Fixture()
        f.probe.onProbe = { f.env.now += 0.01 }
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.monitor.refresh()

        #expect(f.probe.targets.count == 2)
        #expect(f.monitor.outline.rect == Fixture.frameB)
    }

    @Test("AC-26: 遅いアプリでも、クリックでの選び直しはすぐ反映される")
    func clickAdoptionIgnoresSlowBackoff() async {
        let f = Fixture()
        f.probe.onProbe = { f.env.now += 0.05 }
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()
        await f.settle()

        #expect(f.model.target == Fixture.browser)
        #expect(f.env.adoptedCount == 1)
    }

    @Test("AC-26: 挿入先のアプリの入力欄でない所のクリックも、遅いアプリですぐ反映される")
    func clickAwayIgnoresSlowBackoff() async {
        let f = Fixture()
        f.probe.onProbe = { f.env.now += 0.05 }
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        f.focus(Fixture.fieldB, frame: Fixture.frameB, lookup: Fixture.button, in: Fixture.editor)
        f.env.frontmost = Fixture.editor
        f.env.mouse = f.clickPoint(inside: Fixture.frameB)

        f.monitor.handleClick()

        #expect(f.model.target == nil)
    }

    // MARK: - AC-27 枠線がオフのとき

    @Test("AC-27: 枠線がオフでも挿入先は同じに決まり、枠だけが無く、ウィンドウの一覧を取らない")
    func outlineOffKeepsTargetsButNoOutline() async {
        let f = Fixture()
        f.env.isOutlineEnabled = false
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)

        let start = f.open(Fixture.editor)
        #expect(start.target == Fixture.editor)
        #expect(f.monitor.outline.rect == nil)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, lookup: Fixture.button, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == nil)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == nil)

        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.browser)
        f.env.frontmost = Fixture.browser
        f.env.mouse = f.clickPoint(inside: Fixture.frameA)
        f.monitor.handleClick()
        await f.settle()
        #expect(f.model.target == Fixture.browser)
        #expect(f.monitor.outline.rect == nil)

        #expect(f.env.windowListCalls == 0)
    }

    @Test("AC-27: 枠線がオフなら、枠の無い自動表示の結果に要素の枠を読み足さない")
    func outlineOffDoesNotReadElementFrame() {
        let f = Fixture()
        f.env.isOutlineEnabled = false
        let observed = ObservedFocus(
            processIdentifier: Fixture.editor.processIdentifier,
            probe: FocusedElementProbe(element: Fixture.fieldA, lookup: Fixture.textField, frame: nil)
        )

        let start = f.open(Fixture.editor, observedFocus: observed)

        #expect(start.target == Fixture.editor)
        #expect(f.probe.frameRequests.isEmpty)
        #expect(f.probe.targets.isEmpty)
    }

    @Test("AC-27: 枠線がオンのときはウィンドウの一覧を取って枠を出し、オフにすると次の調べから枠が消える")
    func outlineToggleAppliesOnNextRefresh() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)
        #expect(f.env.windowListCalls == 1)
        #expect(f.monitor.outline.rect == Fixture.frameA)

        f.env.isOutlineEnabled = false
        f.monitor.refresh()

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == nil)
        #expect(f.env.windowListCalls == 1)
    }

    // MARK: - 選び直し・入力欄の見張りの補足

    @Test("AC-6: 隠れた入力欄は挿入先のままで枠だけが消える")
    func coveredFieldKeepsTargetWithoutOutline() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.env.windows = [Fixture.window(of: Fixture.browser), Fixture.window(of: Fixture.editor)]
        f.monitor.refresh()

        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == nil)
    }

    @Test("AC-6: 挿入できなかった入力欄は、別の入力欄に移るまで挿入先に戻らず、移ると選び直される")
    func rejectedFieldStaysRejectedUntilFocusMoves() {
        let f = Fixture()
        f.focus(Fixture.fieldA, frame: Fixture.frameA, in: Fixture.editor)
        f.open(Fixture.editor)

        f.monitor.rejectCurrentField()
        #expect(f.model.target == nil)
        #expect(f.monitor.outline.rect == nil)

        f.monitor.refresh()
        #expect(f.model.target == nil)

        f.focus(Fixture.fieldB, frame: Fixture.frameB, in: Fixture.editor)
        f.monitor.refresh()
        #expect(f.model.target == Fixture.editor)
        #expect(f.monitor.outline.rect == Fixture.frameB)
    }
}
