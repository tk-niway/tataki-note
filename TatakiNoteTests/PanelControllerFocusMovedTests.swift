import ApplicationServices
import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerFocusMovedTests {
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let commitAndSendKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    private static let focusMovedMessage = "入力欄を選択し直してください"

    @MainActor
    private final class AnnouncementRecorder {
        private(set) var messages: [String] = []

        func record(_ message: String) {
            messages.append(message)
        }
    }

    private struct Fixture {
        let controller: PanelController
        let library: DraftLibrary
        let inserter: InserterStub
        let saveAnimation: SaveAnimationModel
        let announcements: AnnouncementRecorder
        let field: AXUIElement
    }

    private func withFixture(
        result: InsertionResult,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.animationMode = .off
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let library = DraftLibrary(store: .inMemory)
        let inserter = InserterStub(result: result)
        let probe = FocusedElementProbeStub()
        let field = AXUIElementCreateApplication(pid_t.max)
        probe.result = FocusedElementProbe(
            element: field,
            lookup: WatcherFixture.textFieldLookup,
            frame: nil
        )
        let sleeper = HeldSleeper()
        let announcements = AnnouncementRecorder()
        let saveAnimation = SaveAnimationModel(
            sleep: { await sleeper.sleep($0) },
            announce: { announcements.record($0) }
        )
        let controller = PanelControllerFactory.make(
            settings: settings,
            probe: probe,
            inserter: inserter,
            ownProcessIdentifier: Self.ownPid,
            library: library,
            saveAnimation: saveAnimation,
            animator: FakePanelFrameAnimator(),
            shaker: PanelShakerSpy()
        )
        controller.targetOverride = { Self.textEdit }
        defer {
            controller.panel.orderOut(nil)
            sleeper.releaseAll()
        }
        try await body(Fixture(
            controller: controller,
            library: library,
            inserter: inserter,
            saveAnimation: saveAnimation,
            announcements: announcements,
            field: field
        ))
    }

    @Test(
        "AC-12: フォーカスが移っていたときは、パネルが開いた状態に戻って本文が戻り、「入力欄を選択し直してください」のトーストが注意の印で出て読み上げられ、履歴は空のまま",
        arguments: [false, true]
    )
    func focusMovedShowsNoticeToast(shouldSend: Bool) async throws {
        try await withFixture(result: .focusMoved) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            let key = shouldSend ? Self.commitAndSendKey : Self.commitKey
            #expect(fixture.controller.handleKey(key))
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) { fixture.saveAnimation.toastMessage != nil }

            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.text == "hello")
            #expect(fixture.saveAnimation.toastMessage == Self.focusMovedMessage)
            #expect(fixture.saveAnimation.toastStyle == .notice)
            #expect(fixture.announcements.messages == [Self.focusMovedMessage])
            #expect(fixture.library.history.isEmpty)
        }
    }

    @Test("AC-12: 確定すると、パネルを隠す前に見張っていた入力欄が挿入に渡される")
    func commitPassesTrackedFieldToInserter() async throws {
        try await withFixture(result: .inserted) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            #expect(fixture.controller.handleKey(Self.commitKey))
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) { !fixture.inserter.calls.isEmpty }

            #expect(fixture.inserter.expectedFields.count == 1)
            #expect(fixture.inserter.expectedFields.first.flatMap { $0 }.map { CFEqual($0, fixture.field) } == true)
        }
    }
}
