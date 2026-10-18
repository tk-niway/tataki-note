import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class SharerSpy: TextSharing {
    private(set) var calls: [(text: String, anchor: SharingAnchor)] = []

    func share(_ text: String, from anchor: SharingAnchor) {
        calls.append((text, anchor))
    }
}

@MainActor
private final class ShareChooserSpy: ExportDestinationChoosing {
    private(set) var requestCount = 0

    func chooseDestination(initialName: String, directory: URL, completion: @escaping (URL?) -> Void) {
        requestCount += 1
    }

    func bringToFront() {}
}

@MainActor
private final class ShareHeldSleeper {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func releaseAll() {
        let continuations = waiting
        waiting = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

@MainActor
private final class ShareFixture {
    private static let ownPid: pid_t = 4242
    private static let externalPid: pid_t = 777

    let temp: TemporaryDefaults
    let settings: AppSettings
    let sharer = SharerSpy()
    let chooser = ShareChooserSpy()
    let shaker = PanelShakerSpy()
    let beepSpy = BeepSpy()
    let library = DraftLibrary(store: .inMemory)
    let animator = FakePanelFrameAnimator()
    let sleeper = ShareHeldSleeper()
    let saveAnimation: SaveAnimationModel
    let controller: PanelController

    var model: PanelModel { controller.model }
    var session: DraftSession { controller.session }

    init(isAnimationEnabled: Bool = false) throws {
        temp = try TemporaryDefaults()
        settings = temp.makeSettings()
        settings.panelScreen = .main
        settings.animationMode = isAnimationEnabled ? .on : .off
        settings.isSidebarOpen = false
        let sleeper = sleeper
        saveAnimation = SaveAnimationModel(sleep: { await sleeper.sleep($0) }, announce: { _ in })
        let probe = FocusedElementProbeStub()
        controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: InserterStub(result: .inserted),
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: library,
            saveAnimation: saveAnimation,
            animator: animator,
            shaker: shaker,
            beep: beepSpy.beep,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid),
            exportChooser: chooser,
            sharer: sharer
        )
        controller.targetOverride = {
            InsertionTarget(processIdentifier: Self.externalPid, bundleIdentifier: "com.example.Editor", localizedName: "Editor")
        }
        controller.open()
        for index in animator.calls.indices {
            animator.finish(index)
        }
    }

    func cleanup() {
        sleeper.releaseAll()
        controller.panel.orderOut(nil)
        temp.remove()
    }

    func waitForToast() async throws {
        try await waitUntil(attempts: 100, interval: .milliseconds(20)) { saveAnimation.toastMessage != nil }
    }

    struct Snapshot: Equatable {
        var text: String
        var document: PanelDocument
        var mode: DraftMode
        var targetProcess: pid_t?
        var historyCount: Int
        var isPresented: Bool
    }

    var snapshot: Snapshot {
        Snapshot(
            text: model.text,
            document: session.document,
            mode: session.mode,
            targetProcess: model.target?.processIdentifier,
            historyCount: library.history.count,
            isPresented: model.isPresented
        )
    }
}

@MainActor
struct PanelShareWiringTests {
    @Test("AC-16: 文章があるときのシェアのボタンは、パネルの文章でシェアのメニューをボタンの所に出すよう頼む")
    func shareButtonSharesPanelTextFromTitleBarButton() throws {
        let fixture = try ShareFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "  あいう\nabc  "

        fixture.controller.shareFromButton()

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.sharer.calls.first?.text == "  あいう\nabc  ")
        #expect(fixture.sharer.calls.first?.anchor == .titleBarButton)
    }

    @Test("AC-16: 書き出しの保存ダイアログが開いている間も、シェアのボタンはシェアのメニューを出すよう頼む")
    func shareButtonWorksWhileSavePanelIsOpen() throws {
        let fixture = try ShareFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        #expect(fixture.controller.handleKey(PanelKeyInput(
            keyCode: 1,
            modifiers: [.command, .shift],
            hasMarkedText: false,
            characters: "s"
        )))
        #expect(fixture.chooser.requestCount == 1)

        fixture.controller.shareFromButton()

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.sharer.calls.first?.text == "abc")
        #expect(fixture.chooser.requestCount == 1)
    }

    @Test("AC-17: 空・空白と改行だけのときのシェアのボタンは、メニューを出さず、アニメーションがオフなら警告音と「共有する文章がありません」のトースト", arguments: ["", " \n\t ", "\u{3000}"])
    func emptyTextBeepsWhenAnimationIsOff(text: String) async throws {
        let fixture = try ShareFixture(isAnimationEnabled: false)
        defer { fixture.cleanup() }
        fixture.model.text = text
        let focusBefore = fixture.model.focusRequest

        fixture.controller.shareFromButton()
        try await fixture.waitForToast()

        #expect(fixture.sharer.calls.isEmpty)
        #expect(fixture.beepSpy.count == 1)
        #expect(fixture.shaker.shakeCount == 0)
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.nothingToShareMessage)
        #expect(fixture.saveAnimation.toastStyle == .notice)
        #expect(fixture.model.text == text)
        #expect(fixture.model.focusRequest > focusBefore)
    }

    @Test("AC-17: 空のときのシェアのボタンは、アニメーションがオンならパネルが揺れて警告音は鳴らない")
    func emptyTextShakesWhenAnimationIsOn() async throws {
        let fixture = try ShareFixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }
        fixture.model.text = ""

        fixture.controller.shareFromButton()
        try await fixture.waitForToast()

        #expect(fixture.sharer.calls.isEmpty)
        #expect(fixture.shaker.shakeCount == 1)
        #expect(fixture.beepSpy.count == 0)
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.nothingToShareMessage)
    }

    @Test("AC-18: シェアのメニューを出した後も、パネルは開いたままで、文章・下書き・モード・挿入先・履歴は変わらない")
    func stateIsKeptAfterShare() throws {
        let fixture = try ShareFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        let before = fixture.snapshot

        fixture.controller.shareFromButton()

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.snapshot == before)
        #expect(fixture.model.isPresented)
    }

    @Test("AC-18: ノートの書きかけでもシェアのメニューを出した後の状態は変わらない")
    func stateIsKeptAfterShareInNoteMode() throws {
        let fixture = try ShareFixture()
        defer { fixture.cleanup() }
        fixture.model.text = "abc"
        fixture.session.toggleMode()
        let before = fixture.snapshot

        fixture.controller.shareFromButton()

        #expect(fixture.sharer.calls.count == 1)
        #expect(fixture.snapshot == before)
        #expect(fixture.snapshot.mode == .note)
    }
}
