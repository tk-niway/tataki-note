import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class WindowFrameLocateRecorder {
    var frame: CGRect?
    private(set) var processIdentifiers: [pid_t] = []

    var count: Int { processIdentifiers.count }

    func locate(_ processIdentifier: pid_t) -> CGRect? {
        processIdentifiers.append(processIdentifier)
        return frame
    }
}

@MainActor
struct PanelOpenQueryTests {
    private static let ownPid: pid_t = 4242

    private let editor = WatcherFixture.editor
    private let own = InsertionTarget(processIdentifier: PanelOpenQueryTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let element = AXUIElementCreateApplication(pid_t.max)

    private let screenA = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780)
    )
    private let screenB = ScreenGeometry(
        frame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 780)
    )
    private let rectOnA = CGRect(x: 100, y: 100, width: 200, height: 40)
    private let rectOnB = CGRect(x: 1100, y: 100, width: 200, height: 40)
    private let rectOffScreens = CGRect(x: 5_000, y: 5_000, width: 200, height: 40)
    private let mouseOnA = CGPoint(x: 500, y: 400)
    private let mouseOnB = CGPoint(x: 1500, y: 400)

    private var screens: [ScreenGeometry] { [screenA, screenB] }

    private func withController(
        mode: PanelScreen,
        isTrusted: Bool = true,
        target: InsertionTarget,
        probe: FocusedElementProbeStub? = nil,
        recorder: WindowFrameLocateRecorder,
        _ body: (PanelController) throws -> Void
    ) throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = mode
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: isTrusted),
            notifier: NotifierStub(),
            fieldProbe: probe ?? FocusedElementProbeStub(),
            exposeWebContent: { _ in },
            locateTargetWindowFrame: { recorder.locate($0) },
            ownProcessIdentifier: Self.ownPid
        )
        controller.targetOverride = { target }
        defer { controller.close() }
        try body(controller)
    }

    // MARK: - AC-1

    @Test("AC-1: 「マウスのある画面」「メインの画面」のときは、挿入先があってもウィンドウの一覧を取らない", arguments: [PanelScreen.mouse, PanelScreen.main])
    func listIsNotFetchedForMouseAndMain(mode: PanelScreen) {
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = rectOnB

        let screen = PanelOpenPlacement.screen(
            mode: mode,
            screens: screens,
            mouseLocation: mouseOnA,
            fieldFrame: rectOnB,
            locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
        )

        #expect(recorder.count == 0)
        #expect(screen == screenA)
    }

    @Test("AC-1: パネルを開いても、「マウスのある画面」「メインの画面」ではウィンドウの一覧を取らない", arguments: [PanelScreen.mouse, PanelScreen.main])
    func openDoesNotFetchListForMouseAndMain(mode: PanelScreen) throws {
        for target in [editor, own] {
            let recorder = WindowFrameLocateRecorder()
            try withController(mode: mode, target: target, recorder: recorder) { controller in
                controller.open()
            }
            #expect(recorder.count == 0, "\(target.processIdentifier)")
        }
    }

    // MARK: - AC-2

    @Test("AC-2: 挿入先が無いときは、ウィンドウの一覧を取らずに nil を返す")
    func locatorWithoutTargetDoesNotFetch() {
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = rectOnA

        let locator = PanelController.windowFrameLocator(for: nil, locate: { recorder.locate($0) })

        #expect(locator() == nil)
        #expect(recorder.count == 0)
    }

    @Test("AC-2: 挿入先があるときは、呼ばれた分だけ挿入先のプロセス番号で一覧を取り、枠を返す")
    func locatorWithTargetFetchesForTarget() {
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = rectOnB

        let locator = PanelController.windowFrameLocator(for: editor, locate: { recorder.locate($0) })
        #expect(recorder.count == 0)

        #expect(locator() == rectOnB)
        #expect(recorder.processIdentifiers == [editor.processIdentifier])
    }

    @Test("AC-2: 「挿入先のウィンドウがある画面」では、一覧を1回だけ取り、そのウィンドウが重なる画面を選ぶ")
    func targetWindowModeFetchesOnceAndUsesWindowScreen() {
        let recorder = WindowFrameLocateRecorder()
        recorder.frame = rectOnB

        let screen = PanelOpenPlacement.screen(
            mode: .targetWindow,
            screens: screens,
            mouseLocation: mouseOnA,
            fieldFrame: nil,
            locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
        )

        #expect(recorder.count == 1)
        #expect(screen == screenB)
    }

    @Test("AC-2: パネルを開くとき、「挿入先のウィンドウがある画面」では挿入先のプロセス番号で一覧を1回だけ取る")
    func openFetchesOnceInTargetWindowMode() throws {
        let recorder = WindowFrameLocateRecorder()
        try withController(mode: .targetWindow, target: editor, recorder: recorder) { controller in
            controller.open()
        }
        #expect(recorder.processIdentifiers == [editor.processIdentifier])
    }

    @Test("AC-2: 挿入先が自分自身でも、「挿入先のウィンドウがある画面」では今までどおり一覧を1回取る")
    func openFetchesOnceForOwnAppInTargetWindowMode() throws {
        let recorder = WindowFrameLocateRecorder()
        try withController(mode: .targetWindow, target: own, recorder: recorder) { controller in
            controller.open()
        }
        #expect(recorder.processIdentifiers == [own.processIdentifier])
    }

    // MARK: - AC-3

    @Test("AC-3: 「入力欄の近く」で、入力欄の位置が分かってどれかの画面に重なれば、一覧を取らない")
    func nearFieldWithUsableFieldFrameDoesNotFetch() {
        for (fieldFrame, expected) in [(rectOnA, screenA), (rectOnB, screenB)] {
            let recorder = WindowFrameLocateRecorder()
            recorder.frame = rectOnA

            let screen = PanelOpenPlacement.screen(
                mode: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnA,
                fieldFrame: fieldFrame,
                locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
            )

            #expect(recorder.count == 0)
            #expect(screen == expected)
        }
    }

    @Test("AC-3: 「入力欄の近く」で、入力欄の位置が無い・どの画面にも重ならないときは、一覧を1回取る")
    func nearFieldWithoutUsableFieldFrameFetchesOnce() {
        for fieldFrame in [nil, rectOffScreens] {
            let recorder = WindowFrameLocateRecorder()
            recorder.frame = rectOnB

            let screen = PanelOpenPlacement.screen(
                mode: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnA,
                fieldFrame: fieldFrame,
                locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
            )

            #expect(recorder.count == 1)
            #expect(screen == screenB)
        }
    }

    @Test("AC-3: 入力欄の位置が使えない結果(入力欄でない・入力欄か分からない・フォーカスが無い・位置を教えない・許可が無い・挿入先が自分自身)では、一覧を1回取る")
    func unusableProbeResultsFetchOnce() {
        let button = FocusedElementProbe(element: element, lookup: WatcherFixture.buttonLookup, frame: rectOnA)
        let unknown = FocusedElementProbe(
            element: element,
            lookup: .element(role: "AXGroup", subrole: nil, isSelectedTextRangeSettable: false),
            frame: rectOnA
        )
        let unavailable = FocusedElementProbe(element: nil, lookup: .unavailable, frame: nil)
        let noFocus = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)
        let noFrame = FocusedElementProbe(element: element, lookup: WatcherFixture.textFieldLookup, frame: nil)
        let usable = FocusedElementProbe(element: element, lookup: WatcherFixture.textFieldLookup, frame: rectOnA)

        let cases: [(name: String, probe: FocusedElementProbe, isTrusted: Bool, target: InsertionTarget?, fetches: Int)] = [
            ("入力欄でない", button, true, editor, 1),
            ("入力欄か分からない", unknown, true, editor, 1),
            ("アプリが答えない", unavailable, true, editor, 1),
            ("フォーカスが無い", noFocus, true, editor, 1),
            ("位置を教えない", noFrame, true, editor, 1),
            ("許可が無い", usable, false, editor, 1),
            ("挿入先が無い", usable, true, nil, 1),
            ("入力欄の位置が使える", usable, true, editor, 0),
        ]
        for (name, result, isTrusted, target, fetches) in cases {
            let probe = FocusedElementProbeStub()
            probe.result = result
            let recorder = WindowFrameLocateRecorder()
            recorder.frame = rectOnB

            let fieldFrame = PanelOpenPlacement.fieldFrame(
                mode: .nearFocusedField,
                isTrusted: isTrusted,
                target: target,
                probe: probe,
                primaryScreenHeight: 800
            )
            _ = PanelOpenPlacement.screen(
                mode: .nearFocusedField,
                screens: screens,
                mouseLocation: mouseOnA,
                fieldFrame: fieldFrame,
                locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
            )

            #expect(recorder.count == fetches, "\(name)")
        }
    }

    @Test("AC-3: パネルを開くとき、「入力欄の近く」で入力欄の位置が使えなければ一覧を1回取る(入力欄が無い・許可が無い・挿入先が自分自身)")
    func openFetchesOnceWhenFieldFrameUnusable() throws {
        let cases: [(name: String, isTrusted: Bool, target: InsertionTarget)] = [
            ("フォーカスが無い", true, editor),
            ("許可が無い", false, editor),
            ("挿入先が自分自身", true, own),
        ]
        for (name, isTrusted, target) in cases {
            let recorder = WindowFrameLocateRecorder()
            let probe = FocusedElementProbeStub()
            try withController(
                mode: .nearFocusedField,
                isTrusted: isTrusted,
                target: target,
                probe: probe,
                recorder: recorder
            ) { controller in
                controller.open()
            }
            #expect(recorder.processIdentifiers == [target.processIdentifier], "\(name)")
        }
    }

    // MARK: - AC-4

    private func previousScreen(
        mode: PanelScreen,
        fieldFrame: CGRect?,
        targetWindowFrame: CGRect?,
        mouseLocation: CGPoint
    ) -> ScreenGeometry? {
        if mode == .nearFocusedField, let fieldFrame,
           let screen = PanelPlacement.screenWithLargestOverlap(with: fieldFrame, in: screens) {
            return screen
        }
        return PanelPlacement.screen(
            for: mode,
            screens: screens,
            mouseLocation: mouseLocation,
            targetWindowFrame: mode.usesTargetWindowFrame ? targetWindowFrame : nil
        )
    }

    @Test("AC-4: 4つの方式のすべての組み合わせで、一覧を要るときだけ取る決め方の結果は、先に一覧を取る今の決め方の結果と一致する")
    func screenMatchesPreviousRule() {
        let fieldFrames: [CGRect?] = [nil, rectOnA, rectOnB, rectOffScreens]
        let windowFrames: [CGRect?] = [nil, rectOnA, rectOnB]
        let mouseLocations = [mouseOnA, mouseOnB]
        var combinations = 0

        for mode in PanelScreen.allCases {
            for fieldFrame in fieldFrames {
                for windowFrame in windowFrames {
                    for mouse in mouseLocations {
                        let recorder = WindowFrameLocateRecorder()
                        recorder.frame = windowFrame

                        let actual = PanelOpenPlacement.screen(
                            mode: mode,
                            screens: screens,
                            mouseLocation: mouse,
                            fieldFrame: fieldFrame,
                            locateTargetWindowFrame: { recorder.locate(editor.processIdentifier) }
                        )
                        let expected = previousScreen(
                            mode: mode,
                            fieldFrame: fieldFrame,
                            targetWindowFrame: windowFrame,
                            mouseLocation: mouse
                        )
                        let legacy = PanelOpenPlacement.screen(
                            mode: mode,
                            screens: screens,
                            mouseLocation: mouse,
                            targetWindowFrame: windowFrame,
                            fieldFrame: fieldFrame
                        )

                        #expect(actual == expected, "\(mode) field=\(String(describing: fieldFrame)) window=\(String(describing: windowFrame))")
                        #expect(legacy == expected, "\(mode) field=\(String(describing: fieldFrame)) window=\(String(describing: windowFrame))")
                        #expect(recorder.count <= 1)
                        combinations += 1
                    }
                }
            }
        }

        #expect(combinations == PanelScreen.allCases.count * fieldFrames.count * windowFrames.count * mouseLocations.count)
    }
}
