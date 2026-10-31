import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class InsertionTargetEvents {
    var exposed: [InsertionTarget] = []
    var frontmost: InsertionTarget?
    var mouse = CGPoint.zero
}

@MainActor
private struct InsertionTargetFixture {
    static let ownPid: pid_t = 4242
    static let editor = WatcherFixture.editor
    static let other = WatcherFixture.otherApp
    static let editorElement = AXUIElementCreateApplication(pid_t.max)
    static let otherElement = AXUIElementCreateApplication(pid_t.max - 1)
    static let editorFieldRect = CGRect(x: 100, y: 100, width: 200, height: 40)
    static let otherFieldRect = CGRect(x: 400, y: 300, width: 200, height: 40)
    static let editorWindowBounds = CGRect(x: 0, y: 0, width: 400, height: 250)
    static let otherWindowBounds = CGRect(x: 400, y: 250, width: 600, height: 550)

    let defaults: TemporaryDefaults
    let settings: AppSettings
    let probe: PerAppProbeStub
    let clicks: ClickMonitorStub
    let locator: WindowFrameLocateRecorder
    let inserter: InserterStub
    let events: InsertionTargetEvents
    let box: MonitorBox
    let controller: PanelController

    var session: DraftSession { controller.session }
    var monitor: InsertionTargetMonitor? { box.monitor }

    init(
        newDraftMode: DraftMode,
        isOutlineShown: Bool = true,
        panelScreen: PanelScreen = .nearFocusedField
    ) throws {
        let defaults = try TemporaryDefaults()
        let settings = defaults.makeSettings()
        settings.panelScreen = panelScreen
        settings.newDraftMode = newDraftMode
        settings.isInsertionTargetOutlineShown = isOutlineShown
        settings.animationMode = .off
        let probe = PerAppProbeStub()
        probe.results[Self.editor.processIdentifier] = FocusedElementProbe(
            element: Self.editorElement,
            lookup: WatcherFixture.textFieldLookup,
            frame: Self.editorFieldRect
        )
        probe.elementFrame = Self.editorFieldRect
        let clicks = ClickMonitorStub()
        let locator = WindowFrameLocateRecorder()
        let inserter = InserterStub(result: .inserted)
        let events = InsertionTargetEvents()
        let box = MonitorBox()
        let controller = PanelControllerFactory.make(
            settings: settings,
            probe: probe,
            inserter: inserter,
            exposeWebContent: { events.exposed.append($0) },
            locateTargetWindowFrame: { locator.locate($0) },
            ownProcessIdentifier: Self.ownPid,
            animator: FakePanelFrameAnimator(),
            makeTargetMonitor: { model in
                let monitor = InsertionTargetMonitor(
                    panelModel: model,
                    probe: probe,
                    ownProcessIdentifier: Self.ownPid,
                    exposeWebContent: { events.exposed.append($0) },
                    isOutlineEnabled: { PanelController.isOutlineTrackingEnabled(settings: settings) },
                    frontmostApplication: { events.frontmost },
                    isRunning: { _ in true },
                    onScreenWindows: {
                        [
                            OnScreenWindow(processIdentifier: Self.editor.processIdentifier, layer: 0, bounds: Self.editorWindowBounds),
                            OnScreenWindow(processIdentifier: Self.other.processIdentifier, layer: 0, bounds: Self.otherWindowBounds),
                        ]
                    },
                    mouseLocation: { events.mouse },
                    primaryScreenFrame: { WatcherFixture.primaryScreenFrame },
                    sleep: { _ in },
                    pollsAutomatically: false,
                    addClickMonitor: { clicks.add($0) },
                    removeClickMonitor: { clicks.remove($0) }
                )
                box.monitor = monitor
                return monitor
            }
        )
        controller.targetOverride = { Self.editor }
        self.defaults = defaults
        self.settings = settings
        self.probe = probe
        self.clicks = clicks
        self.locator = locator
        self.inserter = inserter
        self.events = events
        self.box = box
        self.controller = controller
    }

    func finish() {
        controller.close()
        defaults.remove()
    }
}

@MainActor
struct DraftModeInsertionTargetTests {
    private let editor = InsertionTargetFixture.editor
    private let other = InsertionTargetFixture.other

    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780)
    )
    private let fieldE = AXUIElementCreateApplication(pid_t.max)

    // MARK: - AC-19

    @Test("AC-19: 枠の矩形を計算するかの判定は、書きかけのモードに関わらず設定「挿入先の枠線」の値のまま")
    func outlineTrackingFollowsSettingOnly() throws {
        for isShown in [true, false] {
            let fixture = try InsertionTargetFixture(newDraftMode: .insert, isOutlineShown: isShown)
            defer { fixture.finish() }

            #expect(PanelController.isOutlineTrackingEnabled(settings: fixture.settings) == isShown)
            fixture.session.toggleMode()
            #expect(fixture.session.mode == .note)
            #expect(PanelController.isOutlineTrackingEnabled(settings: fixture.settings) == isShown)

            fixture.settings.isInsertionTargetOutlineShown = !isShown
            #expect(PanelController.isOutlineTrackingEnabled(settings: fixture.settings) == !isShown)
        }
    }

    @Test("AC-19: 新しい書きかけのモードがノートでも、パネルを開くと挿入先を調べ、クリックの見張りが働き、枠の矩形が入る", arguments: PanelScreen.allCases)
    func noteDraftOpenLooksUpTarget(panelScreen: PanelScreen) throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .note, panelScreen: panelScreen)
        defer { fixture.finish() }
        #expect(fixture.session.mode == .note)

        fixture.controller.open()

        #expect(fixture.controller.model.isPresented)
        #expect(fixture.controller.model.target == editor)
        #expect(fixture.events.exposed == [editor])
        #expect(fixture.probe.targets.contains(editor))
        #expect(fixture.clicks.activeCount == 1)
        #expect(fixture.monitor?.outline.rect == InsertionTargetFixture.editorFieldRect)
    }

    @Test("AC-19: インサートの書きかけをノートにしてから開いても、挿入先を調べて枠の矩形が入る")
    func toggledNoteDraftOpenLooksUpTarget() throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .insert)
        defer { fixture.finish() }
        fixture.session.toggleMode()

        fixture.controller.open()

        #expect(fixture.session.mode == .note)
        #expect(fixture.controller.model.target == editor)
        #expect(fixture.clicks.activeCount == 1)
        #expect(fixture.monitor?.outline.rect == InsertionTargetFixture.editorFieldRect)
    }

    @Test("AC-19: 枠線の設定がオフなら、ノートの書きかけでも枠の矩形は計算しない。挿入先は調べる")
    func noteDraftWithOutlineOffDoesNotTrackRect() throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .note, isOutlineShown: false)
        defer { fixture.finish() }

        fixture.controller.open()

        #expect(fixture.controller.model.target == editor)
        #expect(fixture.monitor?.outline.rect == nil)
    }

    @Test("AC-19: ノートの書きかけで開いたあと、クリックで別のアプリの入力欄を選び直せ、インサートにするとその挿入先にそのまま挿入できる")
    func noteDraftReselectsByClickAndInsertsAfterSwitchingToInsert() async throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .note)
        defer { fixture.finish() }
        fixture.controller.open()
        fixture.controller.model.text = "abc"
        #expect(fixture.controller.model.target == editor)

        fixture.probe.results[other.processIdentifier] = FocusedElementProbe(
            element: InsertionTargetFixture.otherElement,
            lookup: WatcherFixture.textFieldLookup,
            frame: InsertionTargetFixture.otherFieldRect
        )
        fixture.events.frontmost = other
        fixture.events.mouse = CGPoint(x: 500, y: 480)
        fixture.clicks.fire()

        #expect(fixture.controller.model.target == other)
        #expect(fixture.monitor?.outline.rect == InsertionTargetFixture.otherFieldRect)
        #expect(fixture.session.mode == .note)

        fixture.session.switchToInsert()
        #expect(fixture.session.mode == .insert)
        #expect(fixture.controller.model.target == other)

        fixture.controller.commit()
        #expect(try await waitUntil(attempts: 100, interval: .milliseconds(10)) { !fixture.inserter.calls.isEmpty })
        #expect(fixture.inserter.calls.first?.text == "abc")
        #expect(fixture.inserter.calls.first?.target == other)
    }

    @Test("AC-19: ノートの書きかけでも、最初の挿入先に、インサートへ切り替えた後でそのまま挿入できる")
    func noteDraftInsertsIntoOpeningTargetAfterSwitchingToInsert() async throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .note)
        defer { fixture.finish() }
        fixture.controller.open()
        fixture.controller.model.text = "abc"

        fixture.controller.switchToInsertFromButton()
        fixture.controller.commit()

        #expect(try await waitUntil(attempts: 100, interval: .milliseconds(10)) { !fixture.inserter.calls.isEmpty })
        #expect(fixture.inserter.calls.first?.target == editor)
    }

    // MARK: - AC-20

    @Test("AC-20: ノートの書きかけでも「入力欄の近く」なら入力欄を問い合わせ、その枠を位置の計算に使う")
    func noteDraftNearFieldQueriesFieldAndPlacesNearIt() throws {
        let fixture = try InsertionTargetFixture(newDraftMode: .note, panelScreen: .nearFocusedField)
        defer { fixture.finish() }

        fixture.controller.open()

        #expect(fixture.probe.targets == [editor])
        #expect(fixture.settings.panelScreen == .nearFocusedField)

        let fieldFrame = PanelOpenPlacement.fieldFrame(
            mode: fixture.settings.panelScreen,
            isTrusted: true,
            target: editor,
            probe: fixture.probe,
            primaryScreenHeight: 800
        )
        let expectedField = PanelPlacement.cocoaFrame(fromQuartz: InsertionTargetFixture.editorFieldRect, primaryScreenHeight: 800)
        #expect(fieldFrame == expectedField)

        let screen = PanelOpenPlacement.screen(
            mode: fixture.settings.panelScreen,
            screens: [screenA],
            mouseLocation: CGPoint(x: 900, y: 700),
            fieldFrame: fieldFrame,
            locateTargetWindowFrame: { nil }
        )
        #expect(screen == screenA)
        let frame = PanelOpenPlacement.frame(
            size: CGSize(width: 520, height: 340),
            on: screenA,
            mode: fixture.settings.panelScreen,
            fieldFrame: fieldFrame,
            mouseLocation: CGPoint(x: 900, y: 700)
        )
        #expect(frame.minX == 100)
        #expect(frame.maxY <= expectedField.minY)
    }

    // MARK: - AC-21

    @Test("AC-21: 自動表示は、新しい書きかけのモードに関わらず、「自動表示」「対象のアプリ」の設定どおりに見張って表示する")
    func autoShowFollowsSettingsRegardlessOfDraftMode() throws {
        let cases: [(mode: AutoShowMode, apps: [AutoShowApp], watches: Bool)] = [
            (.allApps, [], true),
            (.selectedApps, [WatcherFixture.editorApp], true),
            (.selectedApps, [WatcherFixture.otherAutoShowApp], false),
            (.off, [], false),
        ]
        for draftMode in DraftMode.allCases {
            for (autoShowMode, apps, watches) in cases {
                let fixture = try WatcherFixture()
                defer { fixture.removeSuite() }
                fixture.settings.newDraftMode = draftMode
                fixture.settings.autoShowMode = autoShowMode
                fixture.settings.autoShowApps = apps
                let label = "draft=\(draftMode) autoShow=\(autoShowMode) apps=\(apps.count)"

                fixture.activate(WatcherFixture.editor)

                #expect(fixture.environment.activeClickMonitorCount == (watches ? 1 : 0), "\(label)")
                #expect(fixture.environment.exposedTargets == (watches ? [WatcherFixture.editor] : []), "\(label)")

                fixture.focusTextField(fieldE)
                fixture.watcher.handleFocusChanged()
                #expect(fixture.showCount == (watches ? 1 : 0), "\(label)")
            }
        }
    }

    @Test("AC-21: 新しい書きかけのモードをノートに変えても、見張っているあいだの自動表示は止まらない")
    func changingNewDraftModeKeepsWatching() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        fixture.settings.newDraftMode = .note

        #expect(fixture.environment.activeClickMonitorCount == 1)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
    }
}
