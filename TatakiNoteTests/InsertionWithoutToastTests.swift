import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionWithoutToastTests {
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let commitAndSendKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

    private struct Fixture {
        let controller: PanelController
        let library: DraftLibrary
        let inserter: InserterStub
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
        settings.animationMode = .off
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let library = DraftLibrary(store: .inMemory)
        let inserter = InserterStub(result: result)
        let probe = FocusedElementProbeStub()
        probe.result = FocusedElementProbe(
            element: AXUIElementCreateApplication(pid_t.max),
            lookup: WatcherFixture.textFieldLookup,
            frame: nil
        )
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: PermissionStub(isTrusted: true),
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: library,
            animator: FakePanelFrameAnimator(),
            shaker: PanelShakerSpy(),
            beep: {},
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        controller.targetOverride = { Self.textEdit }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, library: library, inserter: inserter))
    }

    private func expectInsertedAndRecorded(_ fixture: Fixture) async throws {
        try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !fixture.library.history.isEmpty }
        #expect(fixture.library.history.first?.text == "hello")
        #expect(!fixture.controller.model.isPresented)
        #expect(fixture.controller.model.text.isEmpty)
        #expect(fixture.inserter.calls.count == 1)
    }

    @Test("AC-11: 確定+挿入キーで挿入できると、パネルが閉じて本文が空になり、文章が履歴に残る")
    func commitKeyClosesAndRecordsHistory() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))

            try await expectInsertedAndRecorded(fixture)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == false)
        }
    }

    @Test("AC-11: 確定+送信キーで送信できると、パネルが閉じて本文が空になり、文章が履歴に残る")
    func commitAndSendKeyClosesAndRecordsHistory() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitAndSendKey))

            try await expectInsertedAndRecorded(fixture)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == true)
        }
    }

    @Test("AC-11: 帯のボタンから送信できると、パネルが閉じて本文が空になり、文章が履歴に残る")
    func buttonCommitClosesAndRecordsHistory() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: true)

            try await expectInsertedAndRecorded(fixture)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == true)
        }
    }

    @Test("AC-11: 前面にできなくて挿入されなかったときは、パネルを開き直し、文章は履歴に残らない")
    func notInsertedReopensWithoutHistory() async throws {
        try await withFixture(result: .targetNotActivated) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !fixture.inserter.calls.isEmpty }
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) { fixture.controller.model.isPresented }

            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.text == "hello")
            #expect(fixture.library.history.isEmpty)
        }
    }
}
