import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelCommitButtonTests {
    private static let ownPid: pid_t = 4242
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)
    private let own = InsertionTarget(processIdentifier: PanelCommitButtonTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")

    private struct Fixture {
        let controller: PanelController
        let shaker: PanelShakerSpy
        let beepSpy: BeepSpy
        let inserter: InserterStub
        let permission: PermissionStub

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
    }

    private func withFixture(
        isNoteMode: Bool = false,
        hasTarget: Bool = true,
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
        let shaker = PanelShakerSpy()
        let beepSpy = BeepSpy()
        let inserter = InserterStub(result: .inserted)
        let permission = PermissionStub(isTrusted: true)
        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: permission,
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: DraftLibrary(store: .inMemory),
            animator: FakePanelFrameAnimator(),
            shaker: shaker,
            beep: beepSpy.beep,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        if isNoteMode {
            controller.session.toggleMode()
        }
        if hasTarget {
            controller.targetOverride = { own }
        } else {
            controller.isTargetLookupDisabled = true
        }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, shaker: shaker, beepSpy: beepSpy, inserter: inserter, permission: permission))
    }

    private func waitForInsertion(_ inserter: InserterStub) async {
        for _ in 0..<100 where inserter.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func attachEditor(_ controller: PanelController) throws -> PromptTextView {
        let hostingView = try #require(controller.panel.contentView)
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
        }
        let textView = try #require(Self.firstSubview(of: PromptTextView.self, in: hostingView))
        controller.panel.makeFirstResponder(textView)
        return textView
    }

    private func markText(_ text: String, in textView: PromptTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.setMarkedText(
            text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: Self.noReplacement
        )
    }

    @Test("AC-5: 「挿入」「送信」のボタンは、挿入先へ挿入して(送信は送信も頼んで)パネルを閉じる", arguments: [false, true])
    func buttonInsertsAndCloses(shouldSend: Bool) async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: shouldSend)

            #expect(!fixture.model.isPresented)
            await waitForInsertion(fixture.inserter)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "hello")
            #expect(fixture.inserter.calls.first?.target == own)
            #expect(fixture.inserter.calls.first?.shouldSendAfterInsert == shouldSend)
            #expect(fixture.shaker.shakeCount == 0)
        }
    }

    @Test("AC-11: 本文が空のままボタンを押すと、警告音で知らせて閉じず、挿入も合図もない", arguments: [false, true])
    func buttonWithEmptyTextSignals(shouldSend: Bool) async throws {
        try await withFixture { fixture in
            fixture.controller.open()

            fixture.controller.commitFromButton(shouldSendAfterInsert: shouldSend)

            #expect(fixture.shaker.shakeCount == 0)
            #expect(fixture.beepSpy.count == 1)
            #expect(fixture.model.isPresented)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.model.noTargetAlertCount == 0)
        }
    }

    @Test("AC-5: 挿入先なしでボタンを押すと、合図が増えてパネルは閉じない", arguments: [false, true])
    func buttonWithNoTargetSignalsAndStaysOpen(shouldSend: Bool) async throws {
        try await withFixture(hasTarget: false) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: shouldSend)

            #expect(fixture.model.noTargetAlertCount == 1)
            #expect(fixture.model.isPresented)
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.shaker.shakeCount == 0)
        }
    }

    @Test("AC-14: ノートの書きかけでは、帯の「挿入」「送信」のボタンを押しても何もしない", arguments: [false, true])
    func buttonDoesNothingInNoteMode(shouldSend: Bool) async throws {
        try await withFixture(isNoteMode: true) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"

            fixture.controller.commitFromButton(shouldSendAfterInsert: shouldSend)

            #expect(fixture.model.isPresented)
            #expect(fixture.model.text == "hello")
            #expect(fixture.inserter.calls.isEmpty)
            #expect(fixture.shaker.shakeCount == 0)
        }
    }

    @Test("AC-6: 変換中の文字があるときにボタンを押すと、その文字を確定してから挿入する")
    func buttonCommitsMarkedTextBeforeInserting() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            let textView = try attachEditor(fixture.controller)
            #expect(fixture.model.text.isEmpty)
            markText("にほんご", in: textView)
            #expect(textView.hasMarkedText())

            fixture.controller.commitFromButton(shouldSendAfterInsert: false)

            await waitForInsertion(fixture.inserter)
            #expect(fixture.inserter.calls.count == 1)
            #expect(fixture.inserter.calls.first?.text == "にほんご")
            #expect(fixture.shaker.shakeCount == 0)
            #expect(!fixture.model.isPresented)
        }
    }
}
