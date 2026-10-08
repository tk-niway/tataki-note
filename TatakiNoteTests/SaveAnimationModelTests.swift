import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SaveAnimationModelTests {
    @MainActor
    private final class Recorder {
        var durations: [Duration] = []
        var phases: [SaveAnimationPhase] = []
        var highlightedIDs: [UUID?] = []
        var confirmations: [Bool] = []
        var announcements: [String] = []
        var onSleep: (() -> Void)?

        lazy var model: SaveAnimationModel = SaveAnimationModel(
            sleep: { [weak self] duration in
                guard let self else { return }
                self.durations.append(duration)
                self.phases.append(self.model.phase)
                self.highlightedIDs.append(self.model.highlightedDraftID)
                self.confirmations.append(self.model.isShowingSaveConfirmation)
                self.onSleep?()
                await Task.yield()
            },
            announce: { [weak self] in self?.announcements.append($0) }
        )

        var total: Duration { durations.reduce(.zero, +) }
    }

    private static func event(_ kind: DraftSaveEvent.Kind, sequence: Int = 1) -> DraftSaveEvent {
        DraftSaveEvent(sequence: sequence, kind: kind)
    }

    // MARK: - 閉じているときの吸い込み

    @Test("AC-37: サイドバーが閉じているときの新しい保存は、飛ぶ→吸い込まれる、の順に進んで終わる")
    func closedCreatedFliesThenAbsorbs() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.created(UUID())), isSidebarOpen: false)

        #expect(recorder.phases == [.flying, .absorbing])
        #expect(recorder.durations == [SaveAnimationModel.flyingDuration, SaveAnimationModel.absorbingDuration])
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.highlightedDraftID == nil)
        #expect(recorder.model.isShowingSaveConfirmation == false)
    }

    @Test("AC-37: 閉じているときの吸い込みは全体で 0.8 秒以内")
    func closedCreatedFitsInMaximumTotal() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.created(UUID())), isSidebarOpen: false)

        #expect(recorder.total <= SaveAnimationModel.maximumTotal)
        #expect(recorder.total > .zero)
    }

    @Test("AC-37: 吸い込まれるとき、開閉ボタンの反応のきっかけが1回だけ進む")
    func absorbingTriggersToggleReactionOnce() async {
        let recorder = Recorder()
        let before = recorder.model.absorbCount

        await recorder.model.play(Self.event(.created(UUID())), isSidebarOpen: false)

        #expect(recorder.model.absorbCount == before + 1)
    }

    // MARK: - 開いているときのハイライト

    @Test("AC-38: サイドバーが開いているときの新しい保存は、新しい行をハイライトして元に戻す")
    func openCreatedHighlightsRowThenClears() async {
        let recorder = Recorder()
        let id = UUID()

        await recorder.model.play(Self.event(.created(id)), isSidebarOpen: true)

        #expect(recorder.highlightedIDs == [id])
        #expect(recorder.phases == [.idle])
        #expect(recorder.durations == [SaveAnimationModel.highlightDuration])
        #expect(recorder.model.highlightedDraftID == nil)
    }

    @Test("AC-38: ハイライトは 0.8 秒以内で、吸い込みの動きは出ない")
    func openCreatedFitsInMaximumTotal() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.created(UUID())), isSidebarOpen: true)

        #expect(recorder.total <= SaveAnimationModel.maximumTotal)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.absorbCount == 0)
    }

    // MARK: - 上書きのチェック

    @Test("AC-39: 上書きでは保存のアイコンが一瞬チェックの印に変わって戻る")
    func overwrittenShowsConfirmationThenClears() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.overwritten(UUID())), isSidebarOpen: false)

        #expect(recorder.confirmations == [true])
        #expect(recorder.durations == [SaveAnimationModel.saveConfirmationDuration])
        #expect(recorder.model.isShowingSaveConfirmation == false)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.highlightedDraftID == nil)
    }

    @Test("AC-39: チェックの印は 0.8 秒以内で、サイドバーが開いていても同じ")
    func overwrittenFitsInMaximumTotal() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.overwritten(UUID())), isSidebarOpen: true)

        #expect(recorder.total <= SaveAnimationModel.maximumTotal)
        #expect(recorder.confirmations == [true])
        #expect(recorder.highlightedIDs == [nil])
    }

    @Test("AC-39: 上書きでは「保存しました」をアクセシビリティに知らせる")
    func overwrittenAnnouncesSaved() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.overwritten(UUID())), isSidebarOpen: false)

        #expect(recorder.announcements == [SaveAnimationModel.savedAnnouncement])
    }

    @Test("AC-37, AC-38: 新しい保存では「保存しました」を知らせない")
    func createdDoesNotAnnounce() async {
        let recorder = Recorder()

        await recorder.model.play(Self.event(.created(UUID())), isSidebarOpen: false)
        await recorder.model.play(Self.event(.created(UUID()), sequence: 2), isSidebarOpen: true)

        #expect(recorder.announcements.isEmpty)
    }

    // MARK: - 打ち切りと長さ

    @Test("AC-37, AC-38, AC-39: 新しい保存が来たら前の動きを打ち切って始め直す")
    func newEventInterruptsPreviousAnimation() async {
        let recorder = Recorder()
        let firstID = UUID()
        let secondID = UUID()
        var secondPlay: Task<Void, Never>?
        recorder.onSleep = {
            recorder.onSleep = nil
            secondPlay = Task { @MainActor in
                await recorder.model.play(Self.event(.created(secondID), sequence: 2), isSidebarOpen: true)
            }
        }

        await recorder.model.play(Self.event(.created(firstID)), isSidebarOpen: false)
        await secondPlay?.value

        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.highlightedDraftID == nil)
        #expect(recorder.phases == [.flying, .idle])
        #expect(recorder.highlightedIDs == [nil, secondID])
        #expect(recorder.durations == [SaveAnimationModel.flyingDuration, SaveAnimationModel.highlightDuration])
    }

    @Test("AC-37, AC-38, AC-39: どの動きも合計が maximumTotal 以内に収まる定数になっている")
    func everyAnimationFitsInMaximumTotal() {
        let flyingTotal = SaveAnimationModel.flyingDuration + SaveAnimationModel.absorbingDuration

        #expect(flyingTotal <= SaveAnimationModel.maximumTotal)
        #expect(SaveAnimationModel.highlightDuration <= SaveAnimationModel.maximumTotal)
        #expect(SaveAnimationModel.saveConfirmationDuration <= SaveAnimationModel.maximumTotal)
    }

    // MARK: - パネルとの結びつき

    @MainActor
    private final class PanelFixture {
        let defaultsName = UUID().uuidString
        let settings: AppSettings
        let recorder = Recorder()
        let controller: PanelController

        init(isSidebarOpen: Bool) throws {
            let defaults = try #require(UserDefaults(suiteName: defaultsName))
            settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.isSidebarOpen = isSidebarOpen
            let probe = FocusedElementProbeStub()
            controller = PanelController(
                settings: settings,
                targetTracker: FrontmostAppTracker(workspace: .shared, ownProcessIdentifier: -1),
                permission: PermissionStub(isTrusted: true),
                fieldProbe: probe,
                saveAnimation: recorder.model,
                makeTargetMonitor: InsertionTargetMonitor.testFactory(
                    probe: probe,
                    ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
            )
        }

        func cleanup() {
            controller.close()
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        }

        func waitForSleeps(_ count: Int) async throws {
            try await waitUntil(attempts: 200, interval: .milliseconds(25)) { recorder.durations.count == count }
        }
    }

    @Test("AC-37: 閉じたままのサイドバーで ⌘S の保存をすると、吸い込みの動きが出て、サイドバーは閉じたまま窓の大きさも変わらない")
    func savingWithClosedSidebarPlaysAbsorbWithoutOpeningSidebar() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"
        let sizeBefore = fixture.controller.panel.frame.size

        fixture.controller.session.saveCurrent()
        try await fixture.waitForSleeps(2)

        #expect(fixture.recorder.phases == [.flying, .absorbing])
        #expect(fixture.controller.sidebarModel.isOpen == false)
        #expect(fixture.settings.isSidebarOpen == false)
        #expect(fixture.controller.panel.frame.size == sizeBefore)
    }

    @Test("AC-38: 開いたままのサイドバーで保存すると、新しい行がハイライトされる")
    func savingWithOpenSidebarHighlightsNewRow() async throws {
        let fixture = try PanelFixture(isSidebarOpen: true)
        defer { fixture.cleanup() }
        fixture.controller.model.text = "memo"

        fixture.controller.session.saveCurrent()
        try await fixture.waitForSleeps(1)

        let draftID = try #require(fixture.controller.session.document.savedDraftID)
        #expect(fixture.recorder.highlightedIDs == [draftID])
        #expect(fixture.recorder.phases == [.idle])
    }

    @Test("AC-39: 保存した下書きを表示中の ⌘S で、保存のアイコンがチェックの印になる。書き換えのたびの自動の上書きでは変わらない")
    func overwriteShowsConfirmationButAutosaveDoesNot() async throws {
        let fixture = try PanelFixture(isSidebarOpen: false)
        defer { fixture.cleanup() }
        let session = fixture.controller.session
        fixture.controller.model.text = "memo"
        session.saveCurrent()
        try await fixture.waitForSleeps(2)

        fixture.controller.model.text = "memo edited"
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.recorder.durations.count == 2)

        session.saveCurrent()
        try await fixture.waitForSleeps(3)

        #expect(fixture.recorder.confirmations.last == true)
        #expect(fixture.recorder.announcements == [SaveAnimationModel.savedAnnouncement])
    }
}

private extension PanelDocument {
    var savedDraftID: UUID? {
        if case .savedDraft(let id) = self { return id }
        return nil
    }
}
