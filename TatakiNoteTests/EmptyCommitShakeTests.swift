import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class PanelShakerSpy: PanelShaking {
    private(set) var shakeCount = 0
    private(set) var stopCount = 0
    private(set) var windowVisibilityAtStop: [Bool] = []

    func shake(_ window: NSWindow) {
        shakeCount += 1
    }

    func stop(_ window: NSWindow) {
        stopCount += 1
        windowVisibilityAtStop.append(window.isVisible)
    }
}

@MainActor
struct EmptyCommitShakeTests {
    private static let ownPid: pid_t = 4242
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)
    private let own = InsertionTarget(processIdentifier: EmptyCommitShakeTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")

    private static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    private static let commitAndSendKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command], hasMarkedText: false)
    private static let saveKey = PanelKeyInput(keyCode: 1, modifiers: [.command], hasMarkedText: false, characters: "s")
    private static let escapeKey = PanelKeyInput(keyCode: KeyCode.escape, modifiers: [], hasMarkedText: false)

    private struct Fixture {
        let controller: PanelController
        let shaker: PanelShakerSpy
        let inserter: InserterStub
        let permission: PermissionStub
        let library: DraftLibrary
        let animator: FakePanelFrameAnimator

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }
    }

    private func withFixture(
        animationEnabled: Bool = false,
        isTrusted: Bool = true,
        hasTarget: Bool = true,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .main
        settings.animationMode = animationEnabled ? .on : .off
        settings.commitKey = .commandShiftReturn
        settings.commitAndSendKey = .commandReturn
        let shaker = PanelShakerSpy()
        let inserter = InserterStub(result: .inserted)
        let permission = PermissionStub(isTrusted: isTrusted)
        let library = DraftLibrary(store: .inMemory)
        let animator = FakePanelFrameAnimator()
        let probe = FocusedElementProbeStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: permission,
            fieldProbe: probe,
            exposeWebContent: { _ in },
            ownProcessIdentifier: Self.ownPid,
            library: library,
            animator: animator,
            shaker: shaker,
            makeTargetMonitor: InsertionTargetMonitor.testFactory(probe: probe, ownProcessIdentifier: Self.ownPid)
        )
        if hasTarget {
            controller.targetOverride = { own }
        } else {
            controller.isTargetLookupDisabled = true
        }
        defer { controller.panel.orderOut(nil) }
        try await body(Fixture(controller: controller, shaker: shaker, inserter: inserter, permission: permission, library: library, animator: animator))
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

    // MARK: - 空の確定

    @Test("AC-3: 本文が空のまま確定キー・確定+送信キーを押すと、パネルは閉じず、挿入も権限の要求も合図もなく、1回ずつ揺れる", arguments: [false, true])
    func emptyCommitKeysShakeWithoutClosing(shouldSend: Bool) async throws {
        let scenarios: [(isTrusted: Bool, hasTarget: Bool)] = [(true, true), (true, false), (false, true)]
        for scenario in scenarios {
            try await withFixture(isTrusted: scenario.isTrusted, hasTarget: scenario.hasTarget) { fixture in
                fixture.controller.open()
                #expect(fixture.model.isPresented)
                let key = shouldSend ? Self.commitAndSendKey : Self.commitKey

                #expect(fixture.controller.handleKey(key))

                #expect(fixture.shaker.shakeCount == 1)
                #expect(fixture.model.isPresented)
                #expect(fixture.model.lastDismissal == nil)
                #expect(fixture.inserter.calls.isEmpty)
                #expect(fixture.permission.promptRequestCount == 0)
                #expect(fixture.model.noTargetAlertCount == 0)

                #expect(fixture.controller.handleKey(key))
                #expect(fixture.shaker.shakeCount == 2)
                #expect(fixture.model.isPresented)
            }
        }
    }

    // MARK: - 空の保存

    @Test("AC-4: 本文が空のまま ⌘S を押すと、下書きは増えず、揺れる")
    func emptySaveKeyShakes() async throws {
        try await withFixture { fixture in
            fixture.controller.open()

            #expect(fixture.controller.handleKey(Self.saveKey))

            #expect(fixture.shaker.shakeCount == 1)
            #expect(fixture.library.drafts.isEmpty)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-4: 本文が空のまま保存ボタンを押すと、下書きは増えず、揺れる")
    func emptySaveButtonShakes() async throws {
        try await withFixture { fixture in
            fixture.controller.open()

            fixture.controller.saveDraftFromButton()

            #expect(fixture.shaker.shakeCount == 1)
            #expect(fixture.library.drafts.isEmpty)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-4: 本文があれば ⌘S・保存ボタンは保存して、揺れない")
    func nonEmptySaveDoesNotShake() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            fixture.model.text = "abc"

            #expect(fixture.controller.handleKey(Self.saveKey))
            #expect(fixture.library.drafts.map(\.text) == ["abc"])

            fixture.model.text = "abcd"
            fixture.controller.saveDraftFromButton()

            #expect(fixture.library.drafts.map(\.text) == ["abcd"])
            #expect(fixture.shaker.shakeCount == 0)
        }
    }

    @Test("AC-4: 変換中の文字だけがあるときに保存ボタンを押すと、確定した文字で保存され、揺れない")
    func markedTextOnlySaveDoesNotShake() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            let textView = try attachEditor(fixture.controller)
            #expect(fixture.model.text.isEmpty)
            markText("にほんご", in: textView)
            #expect(textView.hasMarkedText())

            fixture.controller.saveDraftFromButton()

            #expect(fixture.library.drafts.map(\.text) == ["にほんご"])
            #expect(fixture.model.text == "にほんご")
            #expect(fixture.shaker.shakeCount == 0)
        }
    }

    // MARK: - 揺れの開始と後始末

    @Test("AC-20: 開く動きの途中の空の確定・空の保存は揺れず、パネルは開いたまま。動きが終われば揺れる")
    func noShakeWhileOpening() async throws {
        try await withFixture(animationEnabled: true) { fixture in
            fixture.controller.open()
            #expect(fixture.animator.calls.count == 1)

            #expect(fixture.controller.handleKey(Self.commitKey))
            #expect(fixture.controller.handleKey(Self.commitAndSendKey))
            #expect(fixture.controller.handleKey(Self.saveKey))
            fixture.controller.saveDraftFromButton()

            #expect(fixture.shaker.shakeCount == 0)
            #expect(fixture.model.isPresented)

            fixture.animator.finish(0)
            #expect(fixture.controller.handleKey(Self.commitKey))

            #expect(fixture.shaker.shakeCount == 1)
            #expect(fixture.model.isPresented)
        }
    }

    @Test("AC-20: 閉じるボタン・esc・close() でパネルを閉じると、揺れを止める")
    func closingStopsShake() async throws {
        let ways: [(String, (PanelController) -> Void)] = [
            ("close()", { $0.close() }),
            ("閉じるボタン", { $0.closeFromButton() }),
            ("esc", { _ = $0.handleKey(Self.escapeKey) }),
        ]
        for (name, close) in ways {
            try await withFixture { fixture in
                fixture.controller.open()
                #expect(fixture.controller.handleKey(Self.commitKey))
                let stopsBefore = fixture.shaker.stopCount

                close(fixture.controller)

                #expect(fixture.shaker.stopCount == stopsBefore + 1, "\(name)")
                #expect(!fixture.model.isPresented, "\(name)")
            }
        }
    }

    @Test("AC-20: 挿入できた確定・権限なしの確定で閉じると、閉じる前に揺れを止める")
    func committingStopsShake() async throws {
        for isTrusted in [true, false] {
            try await withFixture(isTrusted: isTrusted) { fixture in
                fixture.controller.open()
                #expect(fixture.controller.handleKey(Self.commitKey))
                fixture.model.text = "hello"
                let stopsBefore = fixture.shaker.stopCount

                #expect(fixture.controller.handleKey(Self.commitKey))

                #expect(fixture.shaker.stopCount == stopsBefore + 1, "isTrusted: \(isTrusted)")
                #expect(fixture.shaker.windowVisibilityAtStop.last == true, "isTrusted: \(isTrusted)")
                #expect(!fixture.model.isPresented, "isTrusted: \(isTrusted)")
                if isTrusted {
                    await waitForInsertion(fixture.inserter)
                    #expect(fixture.inserter.calls.count == 1)
                }
            }
        }
    }

    @Test("AC-20: 挿入先なしの確定で閉じないときは、揺れを止めない")
    func noTargetCommitKeepsShake() async throws {
        try await withFixture(hasTarget: false) { fixture in
            fixture.controller.open()
            fixture.model.text = "hello"
            let stopsBefore = fixture.shaker.stopCount

            #expect(fixture.controller.handleKey(Self.commitKey))

            #expect(fixture.shaker.stopCount == stopsBefore)
            #expect(fixture.model.isPresented)
            #expect(fixture.model.noTargetAlertCount == 1)
        }
    }

    @Test("AC-20: サイドバーを開閉する前に、揺れを止める")
    func sidebarToggleStopsShake() async throws {
        try await withFixture { fixture in
            fixture.controller.open()
            #expect(fixture.controller.handleKey(Self.commitKey))
            var stopsBefore = fixture.shaker.stopCount

            fixture.controller.setSidebarOpen(true)
            #expect(fixture.shaker.stopCount == stopsBefore + 1)

            stopsBefore = fixture.shaker.stopCount
            fixture.controller.setSidebarOpen(false)
            #expect(fixture.shaker.stopCount == stopsBefore + 1)
        }
    }
}
