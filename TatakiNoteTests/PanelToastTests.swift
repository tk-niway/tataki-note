import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelToastTests {
    private static let ownPid: pid_t = 4242
    private static let commandN = PanelKeyInput(keyCode: 45, modifiers: [.command], hasMarkedText: false, characters: "n")
    private static let commandS = PanelKeyInput(keyCode: 1, modifiers: [.command], hasMarkedText: false, characters: "s")

    @MainActor
    private final class SleepRecorder {
        var durations: [Duration] = []
        var announcements: [String] = []
        var toastsAtSleep: [String?] = []
        var phasesAtSleep: [SaveAnimationPhase] = []
        var isHolding: Bool
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(isHolding: Bool) {
            self.isHolding = isHolding
        }

        lazy var model: SaveAnimationModel = SaveAnimationModel(
            sleep: { [weak self] duration in
                guard let self else { return }
                self.durations.append(duration)
                self.toastsAtSleep.append(self.model.toastMessage)
                self.phasesAtSleep.append(self.model.phase)
                if self.isHolding {
                    await withCheckedContinuation { self.waiting.append($0) }
                } else {
                    await Task.yield()
                }
            },
            announce: { [weak self] in self?.announcements.append($0) }
        )

        func releaseFirst() {
            guard !waiting.isEmpty else { return }
            waiting.removeFirst().resume()
        }

        func releaseAll() {
            isHolding = false
            let continuations = waiting
            waiting = []
            for continuation in continuations {
                continuation.resume()
            }
        }

        var flyingCount: Int {
            phasesAtSleep.filter { if case .flying = $0 { true } else { false } }.count
        }
    }

    @MainActor
    private final class Fixture {
        let defaultsName = UUID().uuidString
        let recorder: SleepRecorder
        let library = DraftLibrary(store: .inMemory)
        let animator = FakePanelFrameAnimator()
        let controller: PanelController

        init(isHolding: Bool, isOpen: Bool = true) throws {
            recorder = SleepRecorder(isHolding: isHolding)
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.panelScreen = .main
            settings.animationMode = .on
            settings.isSidebarOpen = false
            let probe = FocusedElementProbeStub()
            controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                inserter: InserterStub(result: .inserted),
                permission: PermissionStub(isTrusted: true),
                fieldProbe: probe,
                exposeWebContent: { _ in },
                ownProcessIdentifier: PanelToastTests.ownPid,
                library: library,
                saveAnimation: recorder.model,
                animator: animator,
                beep: {},
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: PanelToastTests.ownPid
                )
            )
            controller.targetOverride = {
                InsertionTarget(processIdentifier: PanelToastTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
            }
            if isOpen {
                controller.open()
                for index in animator.calls.indices {
                    animator.finish(index)
                }
            }
        }

        var model: PanelModel { controller.model }
        var session: DraftSession { controller.session }

        func cleanup() {
            recorder.releaseAll()
            controller.panel.orderOut(nil)
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }

        func settleObservation() async throws {
            try await Task.sleep(for: .milliseconds(100))
        }

        func pollUntil(_ condition: () -> Bool) async throws {
            try await waitUntil(attempts: 200, interval: .milliseconds(25), condition)
        }
    }

    // MARK: - 書きかけを履歴に残した知らせ

    @Test("AC-15: 書きかけがある状態で ⌘N を押すと、書きかけを履歴に残したトーストが出て読み上げられ、トーストの時間で消える")
    func commandNShowsArchivedToast() async throws {
        let fixture = try Fixture(isHolding: true)
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        #expect(fixture.controller.handleKey(Self.commandN))
        try await fixture.pollUntil { fixture.recorder.model.toastMessage != nil }

        #expect(fixture.recorder.model.toastMessage == SaveAnimationModel.archivedMessage)
        #expect(fixture.recorder.announcements == [SaveAnimationModel.archivedMessage])
        #expect(fixture.recorder.durations == [SaveAnimationModel.toastDuration])

        fixture.recorder.releaseAll()
        try await fixture.pollUntil { fixture.recorder.model.toastMessage == nil }
        #expect(fixture.recorder.model.toastMessage == nil)
    }

    @Test("AC-15: 書きかけがある状態で別の下書きを開くと、トーストが出る")
    func openingDraftShowsArchivedToast() async throws {
        let fixture = try Fixture(isHolding: true)
        defer { fixture.cleanup() }
        let draft = try #require(fixture.library.addDraft(text: "draft"))
        fixture.model.text = "abc"

        fixture.session.request(.draft(draft.id))
        try await fixture.pollUntil { fixture.recorder.model.toastMessage != nil }

        #expect(fixture.recorder.model.toastMessage == SaveAnimationModel.archivedMessage)
        #expect(fixture.library.history.first?.text == "abc")
    }

    @Test("AC-15: 新規作成のアイコンで書きかけを履歴に移したときも、トーストが出る")
    func newDraftButtonShowsArchivedToast() async throws {
        let fixture = try Fixture(isHolding: true)
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.controller.newDraftFromButton()
        try await fixture.pollUntil { fixture.recorder.model.toastMessage != nil }

        #expect(fixture.recorder.model.toastMessage == SaveAnimationModel.archivedMessage)
    }

    @Test("AC-15: 書きかけが無い・空白だけ・下書きの表示中の切り替えでは、トーストが出ない")
    func noToastWhenNothingIsArchived() async throws {
        let fixture = try Fixture(isHolding: true)
        defer { fixture.cleanup() }
        let first = try #require(fixture.library.addDraft(text: "first"))
        let second = try #require(fixture.library.addDraft(text: "second"))

        #expect(fixture.controller.handleKey(Self.commandN))
        fixture.model.text = " \n "
        fixture.session.request(.draft(first.id))
        fixture.session.request(.draft(second.id))
        try await fixture.settleObservation()

        #expect(fixture.session.archivedScratchCount == 0)
        #expect(fixture.recorder.model.toastMessage == nil)
        #expect(fixture.recorder.durations.isEmpty)
        #expect(fixture.recorder.announcements.isEmpty)
    }

    @Test("AC-15: パネルが出ていないときは、書きかけを履歴に移してもトーストが出ない")
    func noToastWhilePanelIsHidden() async throws {
        let fixture = try Fixture(isHolding: true, isOpen: false)
        defer { fixture.cleanup() }
        #expect(!fixture.model.isPresented)
        fixture.model.text = "abc"

        fixture.session.request(.newScratch)
        try await fixture.settleObservation()

        #expect(fixture.session.archivedScratchCount == 1)
        #expect(fixture.recorder.model.toastMessage == nil)
        #expect(fixture.recorder.durations.isEmpty)
    }

    @Test("AC-15: トーストを続けて出すと後のトーストにすぐ替わり、前のトーストの消す処理では後のトーストが消えない")
    func laterToastSurvivesEarlierDismissal() async {
        let recorder = SleepRecorder(isHolding: true)
        let first = Task { @MainActor in await recorder.model.showToast("one") }
        await yieldUntil { recorder.durations.count == 1 }
        let second = Task { @MainActor in await recorder.model.showToast("two") }
        await yieldUntil { recorder.durations.count == 2 }

        #expect(recorder.model.toastMessage == "two")
        #expect(recorder.model.toastCount == 2)

        recorder.releaseFirst()
        await first.value
        #expect(recorder.model.toastMessage == "two")

        recorder.releaseAll()
        await second.value
        #expect(recorder.model.toastMessage == nil)
        #expect(recorder.durations == [SaveAnimationModel.toastDuration, SaveAnimationModel.toastDuration])
        #expect(recorder.announcements == ["one", "two"])
    }

    @Test("AC-15: cancel でトーストはすぐ消え、待っていた消す処理が終わっても出し直されない")
    func cancelDismissesArchivedToast() async {
        let recorder = SleepRecorder(isHolding: true)
        let toast = Task { @MainActor in await recorder.model.showToast(SaveAnimationModel.archivedMessage) }
        await yieldUntil { recorder.durations.count == 1 }
        #expect(recorder.model.toastMessage == SaveAnimationModel.archivedMessage)

        recorder.model.cancel()
        #expect(recorder.model.toastMessage == nil)

        recorder.releaseAll()
        await toast.value
        #expect(recorder.model.toastMessage == nil)
    }

    // MARK: - 上書き保存

    @Test("AC-33: 保存の知らせは、新しく下書きにしたときだけトーストを出す")
    func saveEventShowsToastOnlyWhenCreated() {
        #expect(DraftSaveEvent(sequence: 1, kind: .created(UUID())).showsToast)
        #expect(!DraftSaveEvent(sequence: 1, kind: .overwritten(UUID())).showsToast)
    }

    @Test("AC-33: 開いている下書きを ⌘S で上書き保存すると、写しの動きは出るがトーストと読み上げは出ない")
    func overwriteWithKeyPlaysWithoutToast() async throws {
        let fixture = try Fixture(isHolding: false)
        defer { fixture.cleanup() }
        fixture.model.text = "memo"
        _ = fixture.controller.handleKey(Self.commandS)
        try await fixture.pollUntil { fixture.recorder.durations.count == 3 }
        #expect(fixture.recorder.toastsAtSleep == [nil, SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])

        fixture.model.text = "memo edited"
        _ = fixture.controller.handleKey(Self.commandS)
        try await fixture.pollUntil { fixture.recorder.durations.count == 5 }

        #expect(fixture.recorder.flyingCount == 2)
        #expect(fixture.recorder.toastsAtSleep.dropFirst(3).allSatisfy { $0 == nil })
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.model.toastMessage == nil)
        #expect(fixture.recorder.model.arrivalCount == 2)
    }

    @Test("AC-33: 開いている下書きを保存のアイコンで上書き保存しても、トーストと読み上げは出ない")
    func overwriteWithButtonPlaysWithoutToast() async throws {
        let fixture = try Fixture(isHolding: false)
        defer { fixture.cleanup() }
        fixture.model.text = "memo"
        fixture.controller.saveDraftFromButton()
        try await fixture.pollUntil { fixture.recorder.durations.count == 3 }

        fixture.model.text = "memo edited"
        fixture.controller.saveDraftFromButton()
        try await fixture.pollUntil { fixture.recorder.durations.count == 5 }

        #expect(fixture.recorder.flyingCount == 2)
        #expect(fixture.recorder.toastsAtSleep.dropFirst(3).allSatisfy { $0 == nil })
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.model.toastMessage == nil)
    }

    @Test("AC-33: 書きかけを新しく下書きにしたときは、動きとトーストの両方が出る")
    func creatingDraftPlaysWithToast() async throws {
        let fixture = try Fixture(isHolding: false)
        defer { fixture.cleanup() }
        fixture.model.text = "memo"

        _ = fixture.controller.handleKey(Self.commandS)
        try await fixture.pollUntil { fixture.recorder.durations.count == 3 }

        #expect(fixture.recorder.flyingCount == 1)
        #expect(fixture.recorder.toastsAtSleep == [nil, SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])
    }

    @Test("AC-33: showsToast を false にした play は、待ちが 2 回で、トーストを変えず読み上げもしない")
    func playWithoutToastSkipsToastAndLastWait() async {
        let recorder = SleepRecorder(isHolding: false)

        await recorder.model.play(text: "memo", destination: .sidebarToggle, showsToast: false)

        #expect(recorder.durations == [SaveAnimationModel.flyingDuration, SaveAnimationModel.arrivalDuration])
        #expect(recorder.toastsAtSleep == [nil, nil])
        #expect(recorder.announcements.isEmpty)
        #expect(recorder.model.arrivalCount == 1)
        #expect(recorder.model.phase == .idle)
    }
}
