import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SelfInsertionTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: SelfInsertionTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other", localizedName: "Other")

    private struct Fixture {
        var controller: PanelController
        var probe: FocusedElementProbeStub
        var inserter: InserterStub
        var notifier: NotifierStub
    }

    private func withFixture(
        isTrusted: Bool = true,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.panelScreen = .nearFocusedField
        let probe = FocusedElementProbeStub()
        let inserter = InserterStub(result: .inserted)
        let notifier = NotifierStub()
        let controller = PanelController(
            settings: settings,
            targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
            inserter: inserter,
            permission: PermissionStub(isTrusted: isTrusted),
            notifier: notifier,
            fieldProbe: probe,
            ownProcessIdentifier: Self.ownPid
        )
        defer { controller.close() }
        try await body(Fixture(controller: controller, probe: probe, inserter: inserter, notifier: notifier))
    }

    private func waitForInsertion(_ inserter: InserterStub) async {
        for _ in 0..<100 where inserter.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - 挿入先の決め方

    @Test("AC-22: targetOverride が値を返すときは、それがパネルの挿入先になる")
    func overrideBecomesPanelTarget() async throws {
        try await withFixture { fixture in
            fixture.controller.targetOverride = { own }

            fixture.controller.open()

            #expect(fixture.controller.model.target == own)
        }
    }

    @Test("AC-22: targetOverride が nil を返すときは、前面のアプリの挿入先を使う")
    func nilOverrideFallsBackToTracker() async throws {
        try await withFixture(isTrusted: false) { fixture in
            let tracker = FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1)
            let expected = tracker.currentTarget()
            fixture.controller.targetOverride = { nil }

            fixture.controller.open()

            #expect(fixture.controller.model.target == expected)
        }
    }

    // MARK: - アクセシビリティの問い合わせ

    @Test("AC-22: 自分自身が挿入先のときだけ、アクセシビリティの問い合わせをしない")
    func queriesAccessibilityOnlyForOtherApps() {
        #expect(PanelController.shouldQueryAccessibility(of: own, ownProcessIdentifier: Self.ownPid) == false)
        #expect(PanelController.shouldQueryAccessibility(of: other, ownProcessIdentifier: Self.ownPid) == true)
        #expect(PanelController.shouldQueryAccessibility(of: nil, ownProcessIdentifier: Self.ownPid) == false)
    }

    @Test("AC-22: 自分自身が挿入先のパネルを開くときは、入力欄の位置を問い合わせない")
    func opensWithoutProbingWhenTargetIsOwn() async throws {
        try await withFixture { fixture in
            fixture.controller.targetOverride = { own }

            fixture.controller.open()

            #expect(fixture.probe.targets.isEmpty)
        }
    }

    @Test("AC-22: 他のアプリが挿入先のパネルを開くときは、今までどおり入力欄の位置を問い合わせる")
    func opensWithProbingWhenTargetIsOtherApp() async throws {
        try await withFixture { fixture in
            fixture.controller.targetOverride = { other }

            fixture.controller.open()

            #expect(fixture.probe.targets == [other])
        }
    }

    // MARK: - 挿入のときの入力欄の判定

    @Test("AC-22: 自分自身への挿入では入力欄の判定をせずに貼り付け、クリップボードを元に戻す")
    func pastesWithoutFocusCheckForOwnTarget() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)
        let original = PasteboardSnapshot.capture(from: pasteboard)
        let poster = PasteShortcutPosterStub(pasteboard: pasteboard)
        let focusInspector = FocusInspectorStub(state: .notTextInput)
        let activator = ActivatorStub(result: true)
        let inserter = ClipboardTextInserter(
            pasteboard: pasteboard,
            activator: activator,
            poster: poster,
            focusInspector: focusInspector,
            submitSender: SubmitKeySenderStub(pasteboard: pasteboard),
            submitDelay: .zero,
            settleDelay: .zero,
            restoreDelay: .zero,
            ownProcessIdentifier: Self.ownPid
        )

        let result = await inserter.insert("line1\nline2", into: own, shouldSendAfterInsert: false)

        #expect(result == .inserted)
        #expect(activator.targets == [own])
        #expect(focusInspector.targets.isEmpty)
        #expect(poster.records.count == 1)
        #expect(poster.records.first?.string == "line1\nline2")
        #expect(PasteboardSnapshot.capture(from: pasteboard) == original)
    }

    @Test("AC-22: 他のアプリへの挿入では、今までどおり入力欄でなければ貼り付けない")
    func stillChecksFocusForOtherApps() async {
        let pasteboard = PasteboardFixture.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        PasteboardFixture.writeRichContents(to: pasteboard)
        let original = PasteboardSnapshot.capture(from: pasteboard)
        let poster = PasteShortcutPosterStub(pasteboard: pasteboard)
        let focusInspector = FocusInspectorStub(state: .notTextInput)
        let inserter = ClipboardTextInserter(
            pasteboard: pasteboard,
            activator: ActivatorStub(result: true),
            poster: poster,
            focusInspector: focusInspector,
            submitSender: SubmitKeySenderStub(pasteboard: pasteboard),
            submitDelay: .zero,
            settleDelay: .zero,
            restoreDelay: .zero,
            ownProcessIdentifier: Self.ownPid
        )

        let result = await inserter.insert("text", into: other, shouldSendAfterInsert: false)

        #expect(result == .noTextInput)
        #expect(focusInspector.targets == [other])
        #expect(poster.records.isEmpty)
        #expect(PasteboardSnapshot.capture(from: pasteboard) == original)
    }

    // MARK: - 挿入の要求の通知

    @Test("AC-22: 確定で挿入することになったとき、パネルを閉じた後・挿入の前に、文章と挿入先が知らされる")
    func notifiesAfterDismissAndBeforeInsertion() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            controller.targetOverride = { own }
            controller.open()
            controller.model.text = "abc\ndef"
            var requests: [(text: String, target: InsertionTarget)] = []
            var wasPresentedAtRequest: Bool?
            var insertionCountAtRequest: Int?
            controller.onInsertionRequested = { text, target, _ in
                requests.append((text, target))
                wasPresentedAtRequest = controller.model.isPresented
                insertionCountAtRequest = fixture.inserter.calls.count
            }

            controller.commit()
            await waitForInsertion(fixture.inserter)

            #expect(requests.count == 1)
            #expect(requests.first?.text == "abc\ndef")
            #expect(requests.first?.target == own)
            #expect(wasPresentedAtRequest == false)
            #expect(insertionCountAtRequest == 0)
            #expect(fixture.inserter.calls.count == 1)
        }
    }

    @Test("AC-22: 確定では送信しない、確定+送信では送信する、が挿入の知らせに含まれる")
    func notifiesWhetherToSendAfterInsert() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            controller.targetOverride = { own }
            var sendFlags: [Bool] = []
            controller.onInsertionRequested = { _, _, sendsAfterInsert in
                sendFlags.append(sendsAfterInsert)
            }

            controller.open()
            controller.model.text = "first"
            controller.commit()
            controller.open()
            controller.model.text = "second"
            controller.commit(shouldSendAfterInsert: true)

            #expect(sendFlags == [false, true])
        }
    }

    @Test("AC-22: 文章が空・挿入先が無いときは知らされない")
    func doesNotNotifyForEmptyTextOrNoTarget() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            var requestCount = 0
            controller.onInsertionRequested = { _, _, _ in requestCount += 1 }

            controller.targetOverride = { own }
            controller.open()
            controller.commit()

            controller.model.present(target: nil)
            controller.model.text = "text"
            controller.commit()

            #expect(requestCount == 0)
        }
    }

    @Test("AC-22: 許可が無いときは知らされない")
    func doesNotNotifyWithoutPermission() async throws {
        try await withFixture(isTrusted: false) { fixture in
            let controller = fixture.controller
            var requestCount = 0
            controller.onInsertionRequested = { _, _, _ in requestCount += 1 }
            controller.targetOverride = { own }
            controller.open()
            controller.model.text = "text"

            controller.commit()

            #expect(requestCount == 0)
            #expect(fixture.inserter.calls.isEmpty)
        }
    }
}
