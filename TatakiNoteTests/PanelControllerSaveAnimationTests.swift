import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerSaveAnimationTests {
    @MainActor
    fileprivate final class Recorder {
        var durations: [Duration] = []
        var phases: [SaveAnimationPhase] = []
        var glowingIDs: [UUID?] = []
        var toasts: [String?] = []
        var announcements: [String] = []
        var onSleep: (() -> Void)?
        var styleDuringSave: PanelToastStyle?
        var styleDuringNotice: PanelToastStyle?
        var heldSleepIndices: Set<Int> = []

        lazy var model: SaveAnimationModel = SaveAnimationModel(
            sleep: { [weak self] duration in
                guard let self else { return }
                let index = self.durations.count
                self.durations.append(duration)
                self.phases.append(self.model.phase)
                self.glowingIDs.append(self.model.glowingDraftID)
                self.toasts.append(self.model.toastMessage)
                self.onSleep?()
                await Task.yield()
                if self.heldSleepIndices.contains(index) {
                    await withCheckedContinuation { self.waitingSleeps.append($0) }
                }
            },
            announce: { [weak self] in self?.announcements.append($0) }
        )

        private var waitingSleeps: [CheckedContinuation<Void, Never>] = []

        func releaseSleeps() {
            heldSleepIndices = []
            let waiting = waitingSleeps
            waitingSleeps = []
            for continuation in waiting {
                continuation.resume()
            }
        }

        var flyingFlights: [SaveFlight] {
            phases.compactMap { phase in
                if case .flying(let flight) = phase { return flight }
                return nil
            }
        }
    }

    // MARK: - パネルとの結びつき

    @MainActor
    private final class PanelFixture {
        let defaultsName = UUID().uuidString
        let settings: AppSettings
        let recorder = PanelControllerSaveAnimationTests.Recorder()
        let library = DraftLibrary(store: .inMemory)
        let inserter = InserterStub(result: .inserted)
        let permission: PermissionStub
        let animator = FakePanelFrameAnimator()
        let controller: PanelController

        init(
            isSidebarOpen: Bool,
            tab: SidebarTab = .drafts,
            isTrusted: Bool = true,
            animationMode: AnimationMode = .on
        ) throws {
            let defaults = try #require(InMemoryDefaults(suiteName: defaultsName))
            settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.panelScreen = .main
            settings.animationMode = animationMode
            settings.isSidebarOpen = isSidebarOpen
            settings.sidebarTab = tab
            settings.commitKey = .commandShiftReturn
            settings.commitAndSendKey = .commandReturn
            permission = PermissionStub(isTrusted: isTrusted)
            let probe = FocusedElementProbeStub()
            controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                inserter: inserter,
                permission: permission,
                fieldProbe: probe,
                exposeWebContent: { _ in },
                ownProcessIdentifier: PanelControllerSaveAnimationTests.ownPid,
                library: library,
                saveAnimation: recorder.model,
                animator: animator,
                beep: {},
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: PanelControllerSaveAnimationTests.ownPid
                )
            )
            controller.targetOverride = {
                InsertionTarget(processIdentifier: PanelControllerSaveAnimationTests.ownPid, bundleIdentifier: "com.example.TatakiNote", localizedName: "TatakiNote")
            }
            controller.open()
            for index in animator.calls.indices {
                animator.finish(index)
            }
        }

        func cleanup() {
            recorder.releaseSleeps()
            controller.panel.orderOut(nil)
            InMemoryDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }

        func waitForSleeps(_ count: Int) async throws {
            try await waitUntil(attempts: 200, interval: .milliseconds(25)) { recorder.durations.count == count }
        }

        func waitForPhase(_ condition: @escaping (SaveAnimationPhase) -> Bool) async throws {
            try await waitUntil(attempts: 200, interval: .milliseconds(25)) { condition(recorder.model.phase) }
        }

        func pressSave() {
            _ = controller.handleKey(PanelControllerSaveAnimationTests.saveKey)
        }
    }

    @Test("AC-13: 閉じたままのサイドバーで ⌘S の保存をすると、開閉ボタンへ飛び、サイドバーは閉じたまま窓の大きさも変わらない")
    func savingWithClosedSidebarFliesToToggle() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"
        let sizeBefore = fixture.controller.panel.frame.size

        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        let flight = try #require(fixture.recorder.flyingFlights.first)
        #expect(flight.destination == .sidebarToggle)
        #expect(flight.text == "memo")
        #expect(fixture.controller.sidebarModel.isOpen == false)
        #expect(fixture.settings.isSidebarOpen == false)
        #expect(fixture.controller.panel.frame.size == sizeBefore)
    }

    @Test("AC-13: 開いたサイドバーで保存すると、保存した下書きの行へ飛び、その行が光る")
    func savingWithOpenSidebarFliesToNewRow() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        let flight = try #require(fixture.recorder.flyingFlights.first)
        #expect(flight.destination == .draftRow(draftID))
        #expect(fixture.recorder.glowingIDs == [nil, draftID, nil])
    }

    @Test("AC-13: 検索で絞っていて保存した行が見えないときは、「下書き」の切り替えへ飛ぶ")
    func savingWithFilteredListFliesToDraftsTab() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.sidebarModel.query = "zzz"
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        let flight = try #require(fixture.recorder.flyingFlights.first)
        #expect(flight.destination == .draftsTab)
        #expect(fixture.recorder.glowingIDs == [nil, nil, nil])
    }

    @Test("AC-13: 上書きの ⌘S でも、もう一度演出が出る")
    func overwriteAlsoPlays() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"
        fixture.pressSave()
        try await fixture.waitForSleeps(3)
        let draftID = try #require(fixture.controller.session.document.savedDraftID)

        fixture.controller.model.text = "memo edited"
        fixture.pressSave()
        try await fixture.waitForSleeps(5)

        let flights = fixture.recorder.flyingFlights
        #expect(fixture.recorder.model.toastMessage == nil)
        #expect(fixture.recorder.toasts.dropFirst(3).allSatisfy { $0 == nil })
        #expect(flights.count == 2)
        #expect(flights.last?.destination == .sidebarToggle)
        #expect(flights.last?.text == "memo edited")
        #expect(fixture.controller.session.lastSaveEvent?.kind == .overwritten(draftID))
        #expect(fixture.library.drafts.count == 1)
    }

    @Test("AC-14: 履歴を出しているときの ⌘S は、下書きに切り替えてから、保存した行へ飛ぶ")
    func saveKeyFromHistorySwitchesToDrafts() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true, tab: .history)
        defer { fixture.cleanup() }
        fixture.library.recordInsertion(text: "old", appName: "Safari", bundleIdentifier: nil)
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        #expect(fixture.controller.sidebarModel.tab == .drafts)
        let flight = try #require(fixture.recorder.flyingFlights.first)
        #expect(flight.destination == .draftRow(draftID))
    }

    @Test("AC-14: 履歴を出しているときの保存ボタンも、下書きに切り替えてから、保存した行へ飛ぶ")
    func saveButtonFromHistorySwitchesToDrafts() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true, tab: .history)
        defer { fixture.cleanup() }
        fixture.library.recordInsertion(text: "old", appName: "Safari", bundleIdentifier: nil)
        fixture.controller.model.text = "memo"

        fixture.controller.saveDraftFromButton()
        try await fixture.waitForSleeps(3)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        #expect(fixture.controller.sidebarModel.tab == .drafts)
        let flight = try #require(fixture.recorder.flyingFlights.first)
        #expect(flight.destination == .draftRow(draftID))
    }

    // MARK: - 止まる条件

    @Test("AC-16: 書き換えのたびの自動の上書きでは演出が出ない")
    func autosaveDoesNotPlay() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"
        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        fixture.controller.model.text = "memo edited"
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.recorder.durations.count == 3)
        #expect(fixture.library.drafts.map(\.text) == ["memo edited"])
    }

    // MARK: - アニメーションがオフのとき

    @Test("AC-8: アニメーションがオフで ⌘S の保存をすると、飛ばずにトーストだけ出て読み上げられ、下書きは増える")
    func savingWithAnimationOffShowsOnlyToast() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false, animationMode: .off)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(2)

        #expect(fixture.recorder.flyingFlights.isEmpty)
        #expect(fixture.recorder.phases.allSatisfy { $0 == .idle })
        #expect(fixture.recorder.model.arrivalCount == 0)
        #expect(fixture.recorder.toasts == [SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.durations == [.milliseconds(720), .milliseconds(1180)])
        #expect(fixture.library.drafts.map(\.text) == ["memo"])
    }

    @Test("AC-8: アニメーションがオフで保存のアイコンを押しても、飛ばずにトーストだけ出る")
    func savingWithButtonAndAnimationOffShowsOnlyToast() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false, animationMode: .off)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.controller.saveDraftFromButton()
        try await fixture.waitForSleeps(2)

        #expect(fixture.recorder.flyingFlights.isEmpty)
        #expect(fixture.recorder.model.arrivalCount == 0)
        #expect(fixture.recorder.toasts.first == SaveAnimationModel.savedMessage)
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(fixture.library.drafts.count == 1)
    }

    @Test("AC-8: アニメーションがオフなら、上書きの ⌘S でもトーストが出る")
    func overwritingWithAnimationOffShowsToast() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false, animationMode: .off)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"
        fixture.pressSave()
        try await fixture.waitForSleeps(2)
        let draftID = try #require(fixture.controller.session.document.savedDraftID)

        fixture.controller.model.text = "memo edited"
        fixture.pressSave()
        try await fixture.waitForSleeps(4)

        #expect(fixture.controller.session.lastSaveEvent?.kind == .overwritten(draftID))
        #expect(fixture.recorder.toasts.dropFirst(2).first == SaveAnimationModel.savedMessage)
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(fixture.recorder.flyingFlights.isEmpty)
        #expect(fixture.library.drafts.map(\.text) == ["memo edited"])
    }

    @Test("AC-8: アニメーションがオフで、サイドバーを開いて履歴を出しているときに ⌘S で保存すると、下書きのタブに切り替わる")
    func savingFromHistoryWithAnimationOffSwitchesToDrafts() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true, tab: .history, animationMode: .off)
        defer { fixture.cleanup() }
        fixture.library.recordInsertion(text: "old", appName: "Safari", bundleIdentifier: nil)
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(2)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        #expect(fixture.controller.sidebarModel.tab == .drafts)
        #expect(fixture.recorder.flyingFlights.isEmpty)
        #expect(fixture.recorder.model.glowCount == 1)
        #expect(fixture.recorder.glowingIDs == [draftID, nil])
    }

    @Test("AC-9: アニメーションがオフで、サイドバーに保存した行が見えているときは、すぐその行に印が付く")
    func savingWithAnimationOffGlowsVisibleRow() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true, animationMode: .off)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(2)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        #expect(fixture.recorder.glowingIDs == [draftID, nil])
        #expect(fixture.recorder.model.glowCount == 1)
    }

    @Test("AC-10: アニメーションがオンで ⌘S の保存をすると、今までどおり飛んで着いたときに弾む")
    func savingWithAnimationOnStillFlies() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false, animationMode: .on)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.pressSave()
        try await fixture.waitForSleeps(3)

        #expect(fixture.recorder.flyingFlights.count == 1)
        #expect(fixture.recorder.model.arrivalCount == 1)
        #expect(fixture.recorder.toasts == [nil, SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
    }

    @Test("AC-16: パネルを閉じると、飛んでいる途中でも着いたあとのトースト中でも、演出とトーストが止まる")
    func closingStopsAnimation() async throws {
        for blockedIndex in [0, 1] {
            let fixture = try PanelFixture(isSidebarOpen: false)
            defer { fixture.cleanup() }
            fixture.recorder.heldSleepIndices = [blockedIndex]
            fixture.controller.model.text = "memo"
            fixture.pressSave()
            try await fixture.waitForSleeps(blockedIndex + 1)
            if blockedIndex == 1 {
                #expect(fixture.recorder.model.toastMessage == SaveAnimationModel.savedMessage)
            }

            fixture.controller.close()

            #expect(fixture.recorder.model.phase == .idle, "blockedIndex: \(blockedIndex)")
            #expect(fixture.recorder.model.toastMessage == nil, "blockedIndex: \(blockedIndex)")
            fixture.recorder.releaseSleeps()
            try await Task.sleep(for: .milliseconds(50))
            #expect(fixture.recorder.model.phase == .idle, "blockedIndex: \(blockedIndex)")
            #expect(fixture.recorder.model.toastMessage == nil, "blockedIndex: \(blockedIndex)")
        }
    }

    @Test("AC-16: ⌘S の直後に挿入や権限なしの確定で閉じても、演出とトーストが止まる", arguments: [true, false])
    func committingStopsAnimation(isTrusted: Bool) async throws {
        let fixture = try PanelFixture(isSidebarOpen: false, isTrusted: isTrusted)
        defer { fixture.cleanup() }
        fixture.recorder.heldSleepIndices = [0]
        fixture.controller.model.text = "memo"
        fixture.pressSave()
        try await fixture.waitForPhase { if case .flying = $0 { return true } else { return false } }

        #expect(fixture.controller.handleKey(PanelControllerSaveAnimationTests.commitKey))

        #expect(!fixture.controller.model.isPresented)
        #expect(fixture.recorder.model.phase == .idle)
        #expect(fixture.recorder.model.toastMessage == nil)
        fixture.recorder.releaseSleeps()
        if isTrusted {
            await yieldUntil { !fixture.inserter.calls.isEmpty }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.recorder.model.phase == .idle)
        #expect(fixture.recorder.model.toastMessage == nil)
    }

    // MARK: - トーストの種類

    @Test("AC-31: 注意のトーストの後の保存は、動きの有無によらずチェックの印で出る", arguments: [true, false])
    func savedToastIsDoneAfterNotice(isAnimated: Bool) async {
        let recorder = PanelControllerSaveAnimationTests.Recorder()
        await recorder.model.showToast(SaveAnimationModel.nothingToExportMessage, style: .notice)
        #expect(recorder.model.toastStyle == .notice)

        recorder.onSleep = {
            if recorder.model.toastMessage == SaveAnimationModel.savedMessage {
                recorder.styleDuringSave = recorder.model.toastStyle
            }
        }
        await recorder.model.play(text: "memo", destination: .draftsTab, isAnimated: isAnimated)

        #expect(recorder.styleDuringSave == .done)
        #expect(recorder.model.toastStyle == .done)
    }

    @Test("AC-31: 注意のトーストを止めた(cancel)後の種類はチェックの印に戻る")
    func cancelResetsToastStyle() async {
        let recorder = PanelControllerSaveAnimationTests.Recorder()
        recorder.onSleep = {
            if recorder.model.toastMessage != nil {
                recorder.styleDuringNotice = recorder.model.toastStyle
                recorder.model.cancel()
            }
        }
        await recorder.model.showToast(SaveAnimationModel.nothingToShareMessage, style: .notice)

        #expect(recorder.styleDuringNotice == .notice)
        #expect(recorder.model.toastMessage == nil)
        #expect(recorder.model.toastStyle == .done)
    }

    fileprivate static let saveKey = PanelKeyInput(keyCode: 1, modifiers: [.command], hasMarkedText: false, characters: "s")
    fileprivate static let commitKey = PanelKeyInput(keyCode: KeyCode.returnKey, modifiers: [.command, .shift], hasMarkedText: false)
    fileprivate static let ownPid: pid_t = 4242
}

private extension PanelDocument {
    var savedDraftID: UUID? {
        if case .savedDraft(let id) = self { return id }
        return nil
    }
}
