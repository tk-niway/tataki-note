import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerPasteNotConfirmedTests {
    private static let ownPid: pid_t = 4242
    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let commitAndSendKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    private static let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

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
        probe.result = FocusedElementProbe(
            element: AXUIElementCreateApplication(pid_t.max),
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
            announcements: announcements
        ))
    }

    @Test(
        "AC-10: 確かめられなかったときは、パネルが開き直して文章が戻り、送信の有無に応じた文のトーストが注意の印で出て、読み上げられる",
        arguments: [false, true]
    )
    func pasteNotConfirmedShowsNoticeToast(shouldSend: Bool) async throws {
        let message = shouldSend ? "送信できませんでした" : "挿入できませんでした"
        try await withFixture(result: .pasteNotConfirmed) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            let key = shouldSend ? Self.commitAndSendKey : Self.commitKey
            #expect(fixture.controller.handleKey(key))
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) { fixture.saveAnimation.toastMessage != nil }

            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
            #expect(fixture.controller.model.isPresented)
            #expect(fixture.controller.model.text == "hello")
            #expect(fixture.saveAnimation.toastMessage == message)
            #expect(fixture.saveAnimation.toastStyle == .notice)
            #expect(fixture.announcements.messages == [message])
            #expect(fixture.library.history.isEmpty)
        }
    }

    @Test(
        "AC-10: 挿入できたときは、確定+挿入でも確定+送信でも、トーストを出さず読み上げもしない",
        arguments: [
            (InsertionResult.inserted, false),
            (InsertionResult.inserted, true),
            (InsertionResult.insertedIntoSecureField, false),
            (InsertionResult.insertedIntoSecureField, true),
        ]
    )
    func insertedShowsNoToast(result: InsertionResult, shouldSend: Bool) async throws {
        try await withFixture(result: result) { fixture in
            fixture.controller.open()
            fixture.controller.model.text = "hello"

            let key = shouldSend ? Self.commitAndSendKey : Self.commitKey
            #expect(fixture.controller.handleKey(key))
            try await waitUntil(attempts: 200, interval: .milliseconds(10)) {
                !fixture.inserter.calls.isEmpty && !fixture.controller.model.isPresented
            }
            if result == .inserted {
                try await waitUntil(attempts: 200, interval: .milliseconds(10)) { fixture.library.history.count == 1 }
            }
            try? await Task.sleep(for: .milliseconds(60))

            #expect(fixture.saveAnimation.toastMessage == nil)
            #expect(fixture.announcements.messages.isEmpty)
            #expect(!fixture.controller.model.isPresented)
        }
    }
}
