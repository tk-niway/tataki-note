import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class NoteModeEvents {
    var exposed: [InsertionTarget] = []
    var insertions: [String] = []
    var frontmost: InsertionTarget?
    var mouse = CGPoint.zero
}

@MainActor
private final class NoteModeOutlineWindow: InsertionTargetOutlineWindow {
    private(set) var isShown = false

    override var isVisible: Bool { isShown }

    override func orderFrontRegardless() {
        isShown = true
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        isShown = true
    }

    override func orderOut(_ sender: Any?) {
        isShown = false
    }
}

@MainActor
private struct NoteModeFixture {
    static let ownPid: pid_t = 4242
    static let editor = WatcherFixture.editor
    static let own = InsertionTarget(processIdentifier: ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    static let element = AXUIElementCreateApplication(pid_t.max)
    static let fieldRect = CGRect(x: 100, y: 100, width: 200, height: 40)

    let defaults: TemporaryDefaults
    let settings: AppSettings
    let probe: PerAppProbeStub
    let clicks: ClickMonitorStub
    let locator: WindowFrameLocateRecorder
    let events: NoteModeEvents
    let controller: PanelController

    init(mode: AppMode, panelScreen: PanelScreen = .nearFocusedField) throws {
        try self.init(mode: mode, panelScreen: panelScreen, target: Self.editor)
    }

    init(mode: AppMode, panelScreen: PanelScreen, target: InsertionTarget?) throws {
        let defaults = try TemporaryDefaults()
        let settings = defaults.makeSettings()
        settings.panelScreen = panelScreen
        settings.selectAppMode(mode, hotkey: nil)
        let probe = PerAppProbeStub()
        probe.results[Self.editor.processIdentifier] = Self.textInputProbe
        probe.elementFrame = Self.fieldRect
        let clicks = ClickMonitorStub()
        let locator = WindowFrameLocateRecorder()
        let events = NoteModeEvents()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { events.exposed.append($0) },
            locateTargetWindowFrame: { locator.locate($0) },
            ownProcessIdentifier: Self.ownPid,
            makeTargetMonitor: { model in
                InsertionTargetMonitor(
                    panelModel: model,
                    probe: probe,
                    ownProcessIdentifier: Self.ownPid,
                    exposeWebContent: { events.exposed.append($0) },
                    isOutlineEnabled: { settings.isInsertionTargetOutlineActive },
                    frontmostApplication: { events.frontmost },
                    isRunning: { _ in true },
                    onScreenWindows: { [] },
                    mouseLocation: { events.mouse },
                    primaryScreenFrame: { WatcherFixture.primaryScreenFrame },
                    sleep: { _ in },
                    pollsAutomatically: false,
                    addClickMonitor: { clicks.add($0) },
                    removeClickMonitor: { clicks.remove($0) }
                )
            }
        )
        controller.targetOverride = { target }
        controller.onInsertionRequested = { text, _, _ in events.insertions.append(text) }
        self.defaults = defaults
        self.settings = settings
        self.probe = probe
        self.clicks = clicks
        self.locator = locator
        self.events = events
        self.controller = controller
    }

    static var textInputProbe: FocusedElementProbe {
        FocusedElementProbe(element: element, lookup: WatcherFixture.textFieldLookup, frame: fieldRect)
    }

    func finish() {
        controller.close()
        defaults.remove()
    }
}

@MainActor
struct NoteModePanelTests {
    private let editor = NoteModeFixture.editor
    private let own = NoteModeFixture.own

    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780)
    )
    private let screenB = ScreenGeometry(
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 780)
    )
    private let rectOnB = CGRect(x: 1100, y: 100, width: 200, height: 40)
    private let mouseOnA = CGPoint(x: 500, y: 400)
    private let mouseOnB = CGPoint(x: 1500, y: 400)

    private var commitInput: PanelKeyInput {
        PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    }

    private var commitAndSendInput: PanelKeyInput {
        PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    }

    private func observedFocus(for target: InsertionTarget) -> ObservedFocus {
        ObservedFocus(processIdentifier: target.processIdentifier, probe: NoteModeFixture.textInputProbe)
    }

    // MARK: - AC-10

    @Test("AC-10: ノートモードでパネルを開くと、どの出し方でも、Web の中身を出す頼みも問い合わせもクリックの見張りもせず、挿入先は無い", arguments: PanelScreen.allCases, [false, true])
    func noteModeOpenDoesNotLookUpTarget(panelScreen: PanelScreen, hasObservedFocus: Bool) throws {
        for target in [editor, own] {
            let fixture = try NoteModeFixture(mode: .note, panelScreen: panelScreen, target: target)
            defer { fixture.finish() }

            fixture.controller.open(observedFocus: hasObservedFocus ? observedFocus(for: target) : nil)

            #expect(fixture.controller.model.isPresented, "\(target.processIdentifier)")
            #expect(fixture.controller.model.target == nil, "\(target.processIdentifier)")
            #expect(fixture.events.exposed.isEmpty, "\(target.processIdentifier)")
            #expect(fixture.probe.targets.isEmpty, "\(target.processIdentifier)")
            #expect(fixture.probe.frameRequests.isEmpty, "\(target.processIdentifier)")
            #expect(fixture.clicks.added == 0, "\(target.processIdentifier)")
            #expect(fixture.clicks.activeCount == 0, "\(target.processIdentifier)")
        }
    }

    @Test("AC-10: インサートモードでは今までどおり、Web の中身を出す頼みと問い合わせとクリックの見張りが始まり、挿入先が入る")
    func insertModeOpenStillLooksUpTarget() throws {
        let fixture = try NoteModeFixture(mode: .insert)
        defer { fixture.finish() }

        fixture.controller.open()

        #expect(fixture.events.exposed == [editor])
        #expect(fixture.probe.targets == [editor])
        #expect(fixture.clicks.activeCount == 1)
        #expect(fixture.controller.model.target == editor)
    }

    // MARK: - AC-11

    @Test("AC-11: ノートモードで「入力欄の近く」のときは、入力欄を問い合わせず、一覧も取らず、マウスポインタの下に出す")
    func noteModeNearFieldPlacesNearMouse() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .nearFocusedField
        settings.selectAppMode(.note, hotkey: nil)
        let probe = PerAppProbeStub()
        probe.results[editor.processIdentifier] = NoteModeFixture.textInputProbe
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = rectOnB
        let mode = settings.effectivePanelScreen

        let fieldFrame = PanelOpenPlacement.fieldFrame(
            mode: mode,
            isTrusted: true,
            target: editor,
            probe: probe,
            primaryScreenHeight: 800
        )
        let screen = PanelOpenPlacement.screen(
            mode: mode,
            screens: [screenA, screenB],
            mouseLocation: mouseOnB,
            fieldFrame: fieldFrame,
            locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
        )
        let size = CGSize(width: 520, height: 340)
        let frame = try PanelOpenPlacement.frame(
            size: size,
            on: #require(screen),
            mode: mode,
            fieldFrame: fieldFrame,
            mouseLocation: mouseOnB
        )

        #expect(mode == .mouse)
        #expect(fieldFrame == nil)
        #expect(probe.targets.isEmpty)
        #expect(recorder.count == 0)
        #expect(screen == screenB)
        #expect(frame == CGRect(x: 1480, y: 52, width: 520, height: 340))
    }

    @Test("AC-11: ノートモードで「入力欄の近く」以外のときは、選んだ方式のまま効く", arguments: [PanelScreen.mouse, PanelScreen.main, PanelScreen.targetWindow])
    func noteModeKeepsOtherScreenModes(panelScreen: PanelScreen) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = panelScreen
        settings.selectAppMode(.note, hotkey: nil)

        #expect(settings.effectivePanelScreen == panelScreen)
    }

    @Test("AC-11: ノートモードで「挿入先のウィンドウがある画面」のときは、前面だったアプリのウィンドウがある画面に出し、分からなければマウスのある画面に出す")
    func noteModeTargetWindowUsesWindowScreenOrMouseScreen() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.panelScreen = .targetWindow
        settings.selectAppMode(.note, hotkey: nil)
        let cases: [(name: String, windowFrame: CGRect?, expected: ScreenGeometry)] = [
            ("ウィンドウが画面 B", rectOnB, screenB),
            ("ウィンドウが分からない", nil, screenA),
        ]
        for (name, windowFrame, expected) in cases {
            let recorder = WindowFrameLocateRecorder()
            recorder.frame = windowFrame

            let screen = PanelOpenPlacement.screen(
                mode: settings.effectivePanelScreen,
                screens: [screenA, screenB],
                mouseLocation: mouseOnA,
                fieldFrame: nil,
                locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
            )

            #expect(screen == expected, "\(name)")
            #expect(recorder.processIdentifiers == [editor.processIdentifier], "\(name)")
        }
    }

    @Test("AC-11: ノートモードでパネルを開くと、「入力欄の近く」ではウィンドウの一覧を取らず、「挿入先のウィンドウがある画面」では前面のアプリで一覧を1回だけ取る。入力欄は問い合わせない")
    func noteModeOpenFetchesWindowListOnlyForTargetWindow() throws {
        let cases: [(screen: PanelScreen, fetched: [pid_t])] = [
            (.nearFocusedField, []),
            (.targetWindow, [editor.processIdentifier]),
        ]
        for (panelScreen, fetched) in cases {
            let fixture = try NoteModeFixture(mode: .note, panelScreen: panelScreen)
            defer { fixture.finish() }

            fixture.controller.open()

            #expect(fixture.locator.processIdentifiers == fetched, "\(panelScreen)")
            #expect(fixture.probe.targets.isEmpty, "\(panelScreen)")
            #expect(fixture.probe.frameRequests.isEmpty, "\(panelScreen)")
        }
    }

    // MARK: - AC-14

    @Test("AC-14: ノートモードでは、枠線の設定がオンでも枠線を出さない")
    func noteModeNeverShowsOutline() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        settings.isInsertionTargetOutlineShown = true

        for mode in AppMode.allCases {
            settings.selectAppMode(mode, hotkey: nil)
            let shown = InsertionTargetOutlineController.shouldShow(
                isPanelPresented: true,
                isOutlineEnabled: settings.isInsertionTargetOutlineActive,
                rect: rect
            )
            #expect(shown == (mode == .insert), "\(mode)")
        }
    }

    @Test("AC-14: ノートモードのあいだは、パネルが開いて枠が入っても枠線の窓は出ない")
    func outlineWindowStaysHiddenInNoteMode() async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.isInsertionTargetOutlineShown = true
        settings.selectAppMode(.note, hotkey: nil)
        let model = PanelModel()
        let outline = InsertionTargetOutlineModel()
        let window = NoteModeOutlineWindow()
        let controller = InsertionTargetOutlineController(
            outline: outline,
            settings: settings,
            panelModel: model,
            panel: NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true),
            window: window,
            primaryScreenHeight: { 1000 }
        )

        model.present(target: nil)
        outline.update(CGRect(x: 100, y: 200, width: 300, height: 50))
        try await Task.sleep(for: .milliseconds(100))

        #expect(!window.isVisible)
        withExtendedLifetime(controller) {}
    }

    @Test("AC-14: パネルを開いたままノートモードにすると、出ていた枠線の窓が消え、インサートモードに戻すと出る")
    func outlineWindowFollowsModeWhilePresented() async throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.isInsertionTargetOutlineShown = true
        let model = PanelModel()
        let outline = InsertionTargetOutlineModel()
        let window = NoteModeOutlineWindow()
        let controller = InsertionTargetOutlineController(
            outline: outline,
            settings: settings,
            panelModel: model,
            panel: NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true),
            window: window,
            primaryScreenHeight: { 1000 }
        )
        model.present(target: nil)
        outline.update(CGRect(x: 100, y: 200, width: 300, height: 50))
        #expect(try await waitUntil(attempts: 100, interval: .milliseconds(20)) { window.isVisible })

        settings.selectAppMode(.note, hotkey: nil)
        #expect(try await waitUntil(attempts: 100, interval: .milliseconds(20)) { !window.isVisible })

        settings.selectAppMode(.insert, hotkey: nil)
        #expect(try await waitUntil(attempts: 100, interval: .milliseconds(20)) { window.isVisible })
        withExtendedLifetime(controller) {}
    }

    // MARK: - AC-15

    @Test("AC-15: パネルを開いたままノートモードにすると、挿入先が無くなり、クリックの見張りが止まる")
    func switchingToNoteModeWhilePresentedStopsWatching() throws {
        let fixture = try NoteModeFixture(mode: .insert)
        defer { fixture.finish() }
        fixture.controller.open()
        fixture.controller.model.text = "abc"
        #expect(fixture.controller.model.target == editor)
        #expect(fixture.clicks.activeCount == 1)
        let probesBeforeSwitch = fixture.probe.targets.count

        fixture.settings.selectAppMode(.note, hotkey: nil)
        fixture.controller.applyAppMode()

        #expect(fixture.controller.model.target == nil)
        #expect(fixture.clicks.activeCount == 0)
        #expect(fixture.probe.targets.count == probesBeforeSwitch)
    }

    @Test("AC-15: 設定のモードが変わると、パネルは自動でノートモードの動きに切り替わる")
    func noteModeIsAppliedByObservation() async throws {
        let fixture = try NoteModeFixture(mode: .insert)
        defer { fixture.finish() }
        fixture.controller.open()
        #expect(fixture.controller.model.target == editor)

        fixture.settings.selectAppMode(.note, hotkey: nil)
        await yieldUntil { fixture.controller.model.target == nil }

        #expect(fixture.controller.model.target == nil)
        #expect(fixture.clicks.activeCount == 0)
    }

    @Test("AC-15: パネルが閉じているときにモードを変えても、見張りは始まらない")
    func switchingModeWhileClosedDoesNothing() throws {
        let fixture = try NoteModeFixture(mode: .note)
        defer { fixture.finish() }

        fixture.settings.selectAppMode(.insert, hotkey: nil)
        fixture.controller.applyAppMode()

        #expect(fixture.clicks.added == 0)
        #expect(fixture.probe.targets.isEmpty)
    }

    // MARK: - AC-16

    @Test("AC-16: パネルを開いたままインサートモードに戻すと、挿入先なしから始まり、問い合わせずにクリックの見張りが始まり、他のアプリの入力欄をクリックするとそれが挿入先になる")
    func switchingToInsertModeWhilePresentedStartsWatching() throws {
        let fixture = try NoteModeFixture(mode: .note)
        defer { fixture.finish() }
        fixture.controller.open()
        #expect(fixture.controller.model.target == nil)
        #expect(fixture.clicks.added == 0)

        fixture.settings.selectAppMode(.insert, hotkey: nil)
        fixture.controller.applyAppMode()

        #expect(fixture.controller.model.target == nil)
        #expect(fixture.clicks.activeCount == 1)
        #expect(fixture.probe.targets.isEmpty)
        #expect(fixture.probe.frameRequests.isEmpty)
        #expect(fixture.events.exposed.isEmpty)

        fixture.events.frontmost = editor
        fixture.events.mouse = CGPoint(x: 150, y: 680)
        fixture.clicks.fire()

        #expect(fixture.controller.model.target == editor)
        #expect(fixture.probe.targets == [editor])
    }

    @Test("AC-16: 設定のモードが変わると、パネルは自動でインサートモードの動きに切り替わる")
    func insertModeIsAppliedByObservation() async throws {
        let fixture = try NoteModeFixture(mode: .note)
        defer { fixture.finish() }
        fixture.controller.open()
        #expect(fixture.clicks.activeCount == 0)

        fixture.settings.selectAppMode(.insert, hotkey: nil)
        await yieldUntil { fixture.clicks.activeCount == 1 }

        #expect(fixture.clicks.activeCount == 1)
        #expect(fixture.controller.model.target == nil)
        #expect(fixture.probe.targets.isEmpty)
    }
}
