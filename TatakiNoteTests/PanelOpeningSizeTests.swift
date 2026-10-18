import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelOpeningSizeTests {
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let defaultSize = CGSize(width: 600, height: 400)
    private static let draggedSize = CGSize(width: 700, height: 500)
    private let target = InsertionTarget(processIdentifier: PanelOpeningSizeTests.ownPid, bundleIdentifier: "com.example.TextEdit", localizedName: "TextEdit")

    private struct Fixture {
        let controller: PanelController
        let inserter: InserterStub
        let shaker: PanelShakerSpy
        let beepSpy: BeepSpy
    }

    private func withFixture(
        result: InsertionResult = .inserted,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.panelDefaultWidth = Self.defaultSize.width
        settings.panelDefaultHeight = Self.defaultSize.height
        settings.animationMode = .off
        settings.commitKey = .commandShiftReturn
        let inserter = InserterStub(result: result)
        let shaker = PanelShakerSpy()
        let beepSpy = BeepSpy()
        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: DraftLibrary(store: .inMemory),
            animator: FakePanelFrameAnimator(),
            shaker: shaker,
            beep: beepSpy.beep,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        controller.targetOverride = { target }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, inserter: inserter, shaker: shaker, beepSpy: beepSpy))
    }

    private func drag(_ controller: PanelController, to size: CGSize) {
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        controller.panel.setFrame(NSRect(origin: controller.panel.frame.origin, size: size), display: false)
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
    }

    private func openAndDrag(_ controller: PanelController) throws {
        controller.open()
        #expect(controller.panel.frame.size == Self.defaultSize)
        drag(controller, to: Self.draggedSize)
        #expect(controller.heldPanelSize == Self.draggedSize)
    }

    @Test("AC-7: 本文があって閉じて開き直すとドラッグで決めた大きさで開き、本文が空なら既定の大きさで開いて忘れる")
    func textKeepsDraggedSizeAndEmptyDropsIt() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            try openAndDrag(controller)

            controller.model.text = "abc"
            controller.close()
            controller.open()
            #expect(controller.heldPanelSize == Self.draggedSize)
            #expect(controller.panel.frame.size == Self.draggedSize)

            controller.model.text = ""
            controller.close()
            controller.open()
            #expect(controller.heldPanelSize == nil)
            #expect(controller.panel.frame.size == Self.defaultSize)

            controller.model.text = "abc"
            controller.close()
            controller.open()
            #expect(controller.heldPanelSize == nil)
            #expect(controller.panel.frame.size == Self.defaultSize)
        }
    }

    @Test("AC-11: 開いている間にもう一度開いても、空のまま確定して知らせても、ドラッグで決めた大きさは消えない")
    func heldSizeSurvivesReopenWhilePresentedAndEmptyCommit() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            try openAndDrag(controller)

            controller.open()
            #expect(controller.heldPanelSize == Self.draggedSize)
            #expect(controller.panel.frame.size == Self.draggedSize)

            controller.commit()
            #expect(fixture.shaker.shakeCount == 0)
            #expect(fixture.beepSpy.count == 1)
            #expect(controller.model.isPresented)
            #expect(controller.heldPanelSize == Self.draggedSize)
            #expect(controller.panel.frame.size == Self.draggedSize)
        }
    }

    @Test("AC-8: 空白や改行だけの本文で開き直しても、ドラッグで決めた大きさで開く")
    func whitespaceOnlyTextKeepsDraggedSize() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            try openAndDrag(controller)

            controller.model.text = " \n"
            controller.close()
            controller.open()

            #expect(controller.heldPanelSize == Self.draggedSize)
            #expect(controller.panel.frame.size == Self.draggedSize)
        }
    }

    @Test("AC-9: 挿入できたら次は既定の大きさで開く")
    func insertedResetsToDefaultSize() async throws {
        try await withFixture(result: .inserted) { fixture in
            let controller = fixture.controller
            try openAndDrag(controller)
            controller.model.text = "hello"

            #expect(controller.handleKey(Self.commitKey))
            await yieldUntil { controller.heldPanelSize == nil }

            #expect(fixture.inserter.calls.count == 1)
            #expect(controller.heldPanelSize == nil)
            #expect(controller.model.text.isEmpty)
            controller.open()
            #expect(controller.panel.frame.size == Self.defaultSize)
        }
    }

    @Test("AC-9: 挿入できずにパネルが開き直したときは、ドラッグで決めた大きさのまま")
    func notInsertedKeepsDraggedSize() async throws {
        try await withFixture(result: .targetNotActivated) { fixture in
            let controller = fixture.controller
            try openAndDrag(controller)
            controller.model.text = "hello"

            #expect(controller.handleKey(Self.commitKey))
            await yieldUntil { !fixture.inserter.calls.isEmpty }
            await yieldUntil { controller.model.isPresented }

            #expect(fixture.inserter.calls.count == 1)
            #expect(controller.model.isPresented)
            #expect(controller.model.text == "hello")
            #expect(controller.heldPanelSize == Self.draggedSize)
            #expect(controller.panel.frame.size == Self.draggedSize)
        }
    }
}
