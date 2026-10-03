import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class FocusedElementProbeStub: FocusedElementProbing {
    var result: FocusedElementProbe
    private(set) var targets: [InsertionTarget] = []
    private(set) var readsFrameValues: [Bool] = []
    private(set) var frameRequests: [AXUIElement] = []
    var elementFrame: CGRect?

    init() {
        result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
    }

    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe {
        targets.append(target)
        readsFrameValues.append(readsFrame)
        return result
    }

    func frame(of element: AXUIElement) -> CGRect? {
        frameRequests.append(element)
        return elementFrame
    }
}

@MainActor
final class WatcherEnvironment {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)
    var mouseLocation = CGPoint.zero
    var showCount = 0
    var exposedTargets: [InsertionTarget] = []
    var shownFocuses: [ObservedFocus] = []
    private(set) var clickMonitorsAdded = 0
    private(set) var clickMonitorsRemoved = 0
    private var activeClickMonitors: [Int: () -> Void] = [:]

    var activeClickMonitorCount: Int { activeClickMonitors.count }

    func addClickMonitor(_ handler: @escaping () -> Void) -> Any? {
        clickMonitorsAdded += 1
        let token = clickMonitorsAdded
        activeClickMonitors[token] = handler
        return token
    }

    func removeClickMonitor(_ token: Any) {
        clickMonitorsRemoved += 1
        if let token = token as? Int {
            activeClickMonitors[token] = nil
        }
    }

    func fireClick() {
        for handler in activeClickMonitors.values {
            handler()
        }
    }
}

@MainActor
final class WatcherFixture {
    static let primaryScreenFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let editor = InsertionTarget(processIdentifier: pid_t.max, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
    static let otherApp = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")
    static let editorApp = AutoShowApp(bundleIdentifier: "com.example.Editor", name: "Editor")
    static let otherAutoShowApp = AutoShowApp(bundleIdentifier: "com.example.Other", name: "Other")

    static let textFieldLookup = FocusedElementLookup.element(role: "AXTextField", subrole: nil, isSelectedTextRangeSettable: true)
    static let buttonLookup = FocusedElementLookup.element(role: "AXButton", subrole: nil, isSelectedTextRangeSettable: false)

    let settings: AppSettings
    let panelModel: PanelModel
    let probe: FocusedElementProbeStub
    let environment: WatcherEnvironment
    let watcher: FocusedElementWatcher
    private let defaults: UserDefaults
    private let suiteName: String

    init(isTrusted: Bool = true, exposeWebContent: ((InsertionTarget) -> Void)? = nil) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.autoShowMode = .allApps
        let panelModel = PanelModel()
        let probe = FocusedElementProbeStub()
        let environment = WatcherEnvironment()
        let screenFrame = Self.primaryScreenFrame

        self.suiteName = suiteName
        self.defaults = defaults
        self.settings = settings
        self.panelModel = panelModel
        self.probe = probe
        self.environment = environment
        self.watcher = FocusedElementWatcher(
            settings: settings,
            panelModel: panelModel,
            permission: OverriddenAccessibilityPermission(isTrusted: isTrusted),
            probe: probe,
            primaryScreenFrame: { screenFrame },
            mouseLocation: { environment.mouseLocation },
            now: { environment.now },
            exposeWebContent: {
                environment.exposedTargets.append($0)
                exposeWebContent?($0)
            },
            addClickMonitor: { environment.addClickMonitor($0) },
            removeClickMonitor: { environment.removeClickMonitor($0) },
            onShow: {
                environment.showCount += 1
                environment.shownFocuses.append($0)
            }
        )
    }

    func removeSuite() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    var showCount: Int { environment.showCount }

    func advance(by interval: TimeInterval) {
        environment.now += interval
    }

    func activate(_ target: InsertionTarget?) {
        watcher.handleActivation(of: target)
        advance(by: FocusedElementWatcher.activationGrace + 0.01)
    }

    func dismissAndWait(_ dismissal: PanelDismissal = .cancelled) {
        watcher.handlePanelDismissed(dismissal, panelTarget: Self.editor)
        advance(by: FocusedElementWatcher.dismissGrace + 0.01)
    }

    func focusTextField(_ element: AXUIElement, frame: CGRect? = nil) {
        probe.result = FocusedElementProbe(element: element, lookup: Self.textFieldLookup, frame: frame)
    }

    func focusButton(_ element: AXUIElement) {
        probe.result = FocusedElementProbe(element: element, lookup: Self.buttonLookup, frame: nil)
    }
}

@MainActor
struct FocusedElementWatcherTests {
    private let fieldE = AXUIElementCreateApplication(pid_t.max)
    private let fieldF = AXUIElementCreateApplication(4_242)
    private let otherElement = AXUIElementCreateSystemWide()

    private let frameContainingClick = CGRect(x: 50, y: 80, width: 200, height: 40)

    @Test("AC-2: 「全アプリ」で、前面のアプリのフォーカスが入力欄に移るとパネルを出す")
    func showsWhenTextInputFocused() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()

        #expect(fixture.showCount == 1)
        #expect(fixture.probe.targets == [WatcherFixture.editor])
        #expect(fixture.probe.readsFrameValues == [false])
    }

    @Test("AC-1: 自動表示が「オフ」なら、フォーカスが入力欄に移っても入力欄をクリックしても出さない")
    func offDoesNotShow() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.autoShowMode = .off

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 0)
    }

    @Test("AC-3: 「選んだアプリのみ」では一覧に入っているアプリでだけ出し、入っていない・一覧が空・bundle identifier が分からないときは出さない")
    func selectedAppsShowsOnlyForListedApps() throws {
        let noBundle = InsertionTarget(processIdentifier: pid_t.max, bundleIdentifier: nil, localizedName: "Unknown")
        let cases: [(apps: [AutoShowApp], target: InsertionTarget, expected: Int)] = [
            ([WatcherFixture.editorApp], WatcherFixture.editor, 1),
            ([WatcherFixture.otherAutoShowApp, WatcherFixture.editorApp], WatcherFixture.editor, 1),
            ([WatcherFixture.otherAutoShowApp], WatcherFixture.editor, 0),
            ([], WatcherFixture.editor, 0),
            ([WatcherFixture.editorApp], noBundle, 0),
        ]
        for (apps, target, expected) in cases {
            let fixture = try WatcherFixture()
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = .selectedApps
            fixture.settings.autoShowApps = apps

            fixture.activate(target)
            fixture.focusTextField(fieldE)
            fixture.watcher.handleFocusChanged()

            #expect(fixture.showCount == expected, "\(apps.map { $0.bundleIdentifier }) \(String(describing: target.bundleIdentifier))")
        }
    }

    @Test("AC-6: アクセシビリティの許可が無いなら、フォーカスが入力欄に移っても入力欄をクリックしても出さない")
    func untrustedDoesNotShow() throws {
        let fixture = try WatcherFixture(isTrusted: false)
        defer { fixture.removeSuite() }

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 0)
        #expect(fixture.probe.targets.isEmpty)
        #expect(fixture.environment.exposedTargets.isEmpty)
    }

    @Test("AC-7: パネルが開いている間は、別の入力欄にフォーカスが移ってもクリックしても何もせず、挿入先も変わらない")
    func presentedPanelIgnoresFocusAndClicks() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.panelModel.present(target: WatcherFixture.editor)
        let probeCount = fixture.probe.targets.count

        fixture.focusTextField(fieldF, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()
        fixture.activate(WatcherFixture.otherApp)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 1)
        #expect(fixture.probe.targets.count == probeCount)
        #expect(fixture.panelModel.isPresented)
        #expect(fixture.panelModel.target == WatcherFixture.editor)
    }

    @Test("AC-8: アプリが前面になった直後のフォーカスの通知では出さず、切り替えて戻っただけでは出さない")
    func justActivatedDoesNotShow() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }

        fixture.watcher.handleActivation(of: WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.advance(by: FocusedElementWatcher.activationGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 0)

        fixture.advance(by: FocusedElementWatcher.activationGrace)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        fixture.dismissAndWait()
        fixture.activate(WatcherFixture.otherApp)
        fixture.watcher.handleActivation(of: WatcherFixture.editor)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.advance(by: FocusedElementWatcher.activationGrace + 0.01)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-9: パネルを閉じた直後のフォーカスの通知や、閉じたあとに同じ入力欄へ当て直された通知では出直さない")
    func justDismissedDoesNotShowAgain() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        fixture.watcher.handlePanelDismissed(.cancelled, panelTarget: WatcherFixture.editor)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.advance(by: FocusedElementWatcher.dismissGrace)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        fixture.watcher.handlePanelDismissed(.cancelled, panelTarget: WatcherFixture.editor)
        fixture.focusTextField(fieldF)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.advance(by: FocusedElementWatcher.dismissGrace)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 2)
    }

    @Test("AC-9: パネルを閉じると、見張りが閉じた時刻を覚える(開け閉めを繰り返しても覚え直す)")
    func panelDismissalIsObserved() async throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        #expect(fixture.watcher.panelDismissedAt == nil)

        let firstDismissal = fixture.environment.now
        fixture.panelModel.present(target: WatcherFixture.editor)
        fixture.panelModel.dismiss()
        await yieldUntil { fixture.watcher.panelDismissedAt == firstDismissal }
        #expect(fixture.watcher.panelDismissedAt == firstDismissal)

        fixture.advance(by: 10)
        fixture.panelModel.present(target: WatcherFixture.editor)
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(fixture.watcher.panelDismissedAt == firstDismissal)

        fixture.advance(by: 10)
        let secondDismissal = fixture.environment.now
        fixture.panelModel.dismiss()
        await yieldUntil { fixture.watcher.panelDismissedAt == secondDismissal }
        #expect(fixture.watcher.panelDismissedAt == secondDismissal)

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.panelModel.present(target: WatcherFixture.editor)
        fixture.panelModel.dismiss()
        let thirdDismissal = fixture.environment.now
        await yieldUntil { fixture.watcher.panelDismissedAt == thirdDismissal }
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 0)
    }

    @Test("AC-10: 確定で閉じた直後でも同じ入力欄の枠の中をクリックすると出し、枠の外や枠が分からないときは出さない")
    func clickInsideFocusedElementShows() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)

        fixture.focusTextField(fieldE, frame: nil)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)
        fixture.focusTextField(fieldE, frame: CGRect(x: 300, y: 300, width: 100, height: 40))
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)
        fixture.focusTextField(fieldE, frame: CGRect(x: 50, y: 680, width: 200, height: 40))
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)

        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)

        fixture.watcher.handlePanelDismissed(.committed, panelTarget: WatcherFixture.editor)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 2)

        #expect(fixture.probe.readsFrameValues == [true, true, true, true, true])
        fixture.watcher.handleFocusChanged()
        #expect(fixture.probe.readsFrameValues.last == false)
    }

    @Test("AC-11: 前面が TatakiNote 自身なら、フォーカスが入力欄に移っても入力欄をクリックしても出さない")
    func ownAppDoesNotShow() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        let ownApp = InsertionTarget(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: "com.example.TatakiNote",
            localizedName: "TatakiNote"
        )

        fixture.activate(ownApp)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 0)
        #expect(fixture.probe.targets.isEmpty)
        #expect(fixture.environment.exposedTargets.isEmpty)
    }

    @Test("AC-15: 入力欄で出して閉じたあと、同じアプリの別の要素へ移ってから元の入力欄に戻ると出す")
    func returningToFieldWithinSameAppShows() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)

        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.dismissAndWait()

        fixture.focusButton(otherElement)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 2)
    }

    @Test("AC-15: 入力欄で出して閉じたあと、別のアプリへ切り替えて戻っただけでは出さない(別のアプリでフォーカスが動いても)")
    func switchingAppsKeepsSameElementSuppression() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)

        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
        fixture.dismissAndWait()

        fixture.activate(WatcherFixture.otherApp)
        fixture.focusButton(otherElement)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-16: 見張らないアプリ・前面が分からないときは、Web の中身を出させず、フォーカスのある要素も問い合わせない")
    func unwatchedAppsAreNotProbed() throws {
        let unwatched: [(mode: AutoShowMode, apps: [AutoShowApp], target: InsertionTarget?)] = [
            (.selectedApps, [WatcherFixture.otherAutoShowApp], WatcherFixture.editor),
            (.selectedApps, [], WatcherFixture.editor),
            (.selectedApps, [WatcherFixture.editorApp], InsertionTarget(processIdentifier: pid_t.max, bundleIdentifier: nil)),
            (.off, [WatcherFixture.editorApp], WatcherFixture.editor),
            (.allApps, [], nil),
            (.allApps, [], InsertionTarget(processIdentifier: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: "com.example.TatakiNote")),
        ]
        for (mode, apps, target) in unwatched {
            let fixture = try WatcherFixture()
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = mode
            fixture.settings.autoShowApps = apps

            fixture.activate(target)
            fixture.focusTextField(fieldE, frame: frameContainingClick)
            fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
            fixture.watcher.handleFocusChanged()
            fixture.watcher.handleClick()

            let label = "\(mode) \(apps.map { $0.bundleIdentifier }) \(String(describing: target))"
            #expect(fixture.environment.exposedTargets.isEmpty, "\(label)")
            #expect(fixture.probe.targets.isEmpty, "\(label)")
            #expect(fixture.showCount == 0, "\(label)")
        }
    }

    @Test("AC-16: 「全アプリ」と、「選んだアプリのみ」で選んだアプリは、前面になったときに Web の中身を出させ、フォーカスのある要素を問い合わせる")
    func watchedAppsAreProbed() throws {
        let watched: [(mode: AutoShowMode, apps: [AutoShowApp])] = [
            (.allApps, []),
            (.selectedApps, [WatcherFixture.editorApp]),
        ]
        for (mode, apps) in watched {
            let fixture = try WatcherFixture()
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = mode
            fixture.settings.autoShowApps = apps

            fixture.activate(WatcherFixture.editor)
            #expect(fixture.environment.exposedTargets == [WatcherFixture.editor], "\(mode)")

            fixture.focusTextField(fieldE)
            fixture.watcher.handleFocusChanged()
            #expect(fixture.probe.targets == [WatcherFixture.editor], "\(mode)")
            #expect(fixture.showCount == 1, "\(mode)")
        }
    }

    @Test("AC-16: 見張っているアプリを対象から外すと、次にアプリが前面になる前でも問い合わせない")
    func removingAppFromListStopsProbing() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.autoShowMode = .selectedApps
        fixture.settings.autoShowApps = [WatcherFixture.editorApp]
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.exposedTargets == [WatcherFixture.editor])

        fixture.settings.autoShowApps = [WatcherFixture.otherAutoShowApp]
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.probe.targets.isEmpty)
        #expect(fixture.showCount == 0)
    }
}
