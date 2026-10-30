import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SaveAnimationModelTests {
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

    // MARK: - 目的地

    @Test("AC-13: 目的地は、閉じていれば開閉ボタン、下書きを出していて行が見えればその行、見えなければ「下書き」の切り替え、履歴を出していれば「下書き」の切り替え")
    func destinationResolution() {
        let saved = UUID()
        let other = UUID()

        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: false, isShowingDrafts: true, visibleDraftIDs: [saved]) == .sidebarToggle)
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: false, isShowingDrafts: false, visibleDraftIDs: []) == .sidebarToggle)
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: true, isShowingDrafts: true, visibleDraftIDs: [saved, other]) == .draftRow(saved))
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: true, isShowingDrafts: true, visibleDraftIDs: [other, saved]) == .draftRow(saved))
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: true, isShowingDrafts: true, visibleDraftIDs: [other]) == .draftsTab)
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: true, isShowingDrafts: true, visibleDraftIDs: []) == .draftsTab)
        #expect(SaveFlightDestination.resolve(savedDraftID: saved, isSidebarOpen: true, isShowingDrafts: false, visibleDraftIDs: [saved]) == .draftsTab)
    }

    @Test("AC-13: 粒は 14 個で、向きは円を等分し、距離は 22〜52pt に収まる")
    func burstParticles() {
        #expect(SaveBurst.particleCount == 14)
        #expect(SaveBurst.particle(at: 0).angle == 0)
        #expect(abs(SaveBurst.particle(at: 7).angle - .pi) < 1e-9)
        for index in 0..<SaveBurst.particleCount {
            let particle = SaveBurst.particle(at: index)
            #expect(particle.distance >= 22)
            #expect(particle.distance <= 52)
            #expect(abs(particle.angle - Double(index) / 14 * 2 * .pi) < 1e-9)
        }
        let distances = Set((0..<SaveBurst.particleCount).map { SaveBurst.particle(at: $0).distance })
        #expect(distances.count > 1)
    }

    @Test("AC-14: 保存の前に下書きへ切り替えるのは、開いていて履歴を出しているときだけ")
    func switchToDraftsBoundaries() {
        #expect(SaveFlightDestination.shouldSwitchToDrafts(isSidebarOpen: true, tab: .history))
        #expect(!SaveFlightDestination.shouldSwitchToDrafts(isSidebarOpen: true, tab: .drafts))
        #expect(!SaveFlightDestination.shouldSwitchToDrafts(isSidebarOpen: false, tab: .history))
        #expect(!SaveFlightDestination.shouldSwitchToDrafts(isSidebarOpen: false, tab: .drafts))
    }

    // MARK: - 演出の進み方

    @Test("AC-12: 飛ぶ→着く→終わる、の順に進み、待ちは 680・720・1180ms。着いたときに弾みが 1 つ進み、行が光り、トーストを出して読み上げる")
    func playSequence() async {
        let recorder = Recorder()
        let id = UUID()
        let flight = SaveFlight(id: 1, text: "memo", destination: .draftRow(id))

        await recorder.model.play(text: "memo", destination: .draftRow(id))

        #expect(recorder.durations == [.milliseconds(680), .milliseconds(720), .milliseconds(1180)])
        #expect(recorder.phases == [.flying(flight), .arrived(flight), .idle])
        #expect(recorder.glowingIDs == [nil, id, nil])
        #expect(recorder.toasts == [nil, SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(SaveAnimationModel.savedMessage == "下書きに保存しました")
        #expect(SaveAnimationModel.toastDuration == .milliseconds(1900))
        #expect(recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(recorder.model.arrivalCount == 1)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.glowingDraftID == nil)
        #expect(recorder.model.toastMessage == nil)
    }

    @Test("AC-15: 行以外の目的地では行は光らないが、弾みとトーストは出る")
    func nonRowDestinationDoesNotGlow() async {
        let recorder = Recorder()

        await recorder.model.play(text: "memo", destination: .sidebarToggle)
        await recorder.model.play(text: "memo", destination: .draftsTab)

        #expect(recorder.glowingIDs.allSatisfy { $0 == nil })
        #expect(recorder.model.arrivalCount == 2)
        #expect(recorder.announcements.count == 2)
        #expect(recorder.toasts.contains(SaveAnimationModel.savedMessage))
    }

    // MARK: - 打ち切り

    @Test("AC-16: 演出の途中でもう一度保存すると、前の演出の残りの待ちは段を変えず、新しい演出が始め直す")
    func newPlayInterruptsPrevious() async {
        let recorder = Recorder()
        recorder.heldSleepIndices = [0]
        let firstPlay = Task { @MainActor in
            await recorder.model.play(text: "first", destination: .sidebarToggle)
        }
        await yieldUntil { recorder.durations.count == 1 }

        await recorder.model.play(text: "second", destination: .draftsTab)
        recorder.releaseSleeps()
        await firstPlay.value

        let first = SaveFlight(id: 1, text: "first", destination: .sidebarToggle)
        let second = SaveFlight(id: 2, text: "second", destination: .draftsTab)
        #expect(recorder.phases.first == .flying(first))
        #expect(recorder.phases.dropFirst().first == .flying(second))
        #expect(recorder.phases.dropFirst(2).first == .arrived(second))
        #expect(recorder.durations.count == 4)
        #expect(recorder.model.arrivalCount == 1)
        #expect(recorder.announcements.count == 1)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.toastMessage == nil)
    }

    @Test("AC-16: cancel で演出とトーストをすぐ止め、残りの待ちが終わっても何も起きない")
    func cancelStopsEverything() async {
        let recorder = Recorder()
        recorder.onSleep = {
            if recorder.durations.count == 2 {
                recorder.model.cancel()
            }
        }

        await recorder.model.play(text: "memo", destination: .draftRow(UUID()))

        #expect(recorder.toasts == [nil, SaveAnimationModel.savedMessage])
        #expect(recorder.durations.count == 2)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.glowingDraftID == nil)
        #expect(recorder.model.toastMessage == nil)
    }

    // MARK: - 動きを使わないとき

    @Test("AC-8: isAnimated が false なら飛ばず、段は idle のまま弾みは進まず、トーストを出して読み上げ、待ちは 720・1180ms")
    func playWithoutMotionShowsOnlyToast() async {
        let recorder = Recorder()

        await recorder.model.play(text: "memo", destination: .sidebarToggle, isAnimated: false)

        #expect(recorder.durations == [.milliseconds(720), .milliseconds(1180)])
        #expect(recorder.phases == [.idle, .idle])
        #expect(recorder.toasts == [SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(recorder.model.arrivalCount == 0)
        #expect(recorder.model.phase == .idle)
        #expect(recorder.model.toastMessage == nil)
    }

    @Test("AC-8: isAnimated が false なら、showsToast が false でもトーストを出す")
    func playWithoutMotionShowsToastEvenWhenOverwriting() async {
        let recorder = Recorder()

        await recorder.model.play(text: "memo", destination: .draftsTab, showsToast: false, isAnimated: false)

        #expect(recorder.toasts == [SaveAnimationModel.savedMessage, SaveAnimationModel.savedMessage])
        #expect(recorder.announcements == [SaveAnimationModel.savedMessage])
        #expect(recorder.model.arrivalCount == 0)
    }

    @Test("AC-9: isAnimated が false で行が目的地なら、すぐ印が付いて 720ms で外れ、印のきっかけが 1 つ進む。行以外では印は付かない")
    func playWithoutMotionGlowsRowImmediately() async {
        let recorder = Recorder()
        let id = UUID()

        await recorder.model.play(text: "memo", destination: .draftRow(id), isAnimated: false)

        #expect(recorder.glowingIDs == [id, nil])
        #expect(recorder.model.glowCount == 1)
        #expect(recorder.model.glowingDraftID == nil)

        await recorder.model.play(text: "memo", destination: .draftsTab, isAnimated: false)
        await recorder.model.play(text: "memo", destination: .sidebarToggle, isAnimated: false)

        #expect(recorder.glowingIDs.dropFirst(2).allSatisfy { $0 == nil })
        #expect(recorder.model.glowCount == 1)
    }

    @Test("AC-9: 同じ行をすぐもう一度保存すると、印のきっかけがもう 1 つ進み、印はその行のままで、前の残りの待ちは何もしない")
    func playWithoutMotionTwiceOnSameRowRestartsGlow() async {
        let recorder = Recorder()
        let id = UUID()
        recorder.heldSleepIndices = [0, 1]
        let first = Task { @MainActor in
            await recorder.model.play(text: "memo", destination: .draftRow(id), isAnimated: false)
        }
        await yieldUntil { recorder.durations.count == 1 }
        let second = Task { @MainActor in
            await recorder.model.play(text: "memo", destination: .draftRow(id), isAnimated: false)
        }
        await yieldUntil { recorder.durations.count == 2 }

        #expect(recorder.model.glowCount == 2)
        #expect(recorder.model.glowingDraftID == id)
        #expect(recorder.model.toastMessage == SaveAnimationModel.savedMessage)

        recorder.releaseSleeps()
        await first.value
        await second.value

        #expect(recorder.durations.count == 3)
        #expect(recorder.announcements.count == 2)
        #expect(recorder.model.glowCount == 2)
        #expect(recorder.model.glowingDraftID == nil)
        #expect(recorder.model.toastMessage == nil)
    }

    @Test("AC-9: isAnimated が false の途中で cancel すると、印とトーストをすぐ消し、残りの待ちが終わっても何も起きない")
    func cancelStopsPlayWithoutMotion() async {
        let recorder = Recorder()
        recorder.onSleep = {
            if recorder.durations.count == 1 {
                recorder.model.cancel()
            }
        }

        await recorder.model.play(text: "memo", destination: .draftRow(UUID()), isAnimated: false)

        #expect(recorder.durations.count == 1)
        #expect(recorder.model.glowingDraftID == nil)
        #expect(recorder.model.toastMessage == nil)
        #expect(recorder.model.phase == .idle)
    }

    @Test("AC-10: isAnimated が true なら今までどおり飛び、着いたときに弾みと印のきっかけがそれぞれ 1 つ進む")
    func playWithMotionAdvancesGlowCountOnArrival() async {
        let recorder = Recorder()
        let id = UUID()

        await recorder.model.play(text: "memo", destination: .draftRow(id), isAnimated: true)

        #expect(recorder.flyingFlights.count == 1)
        #expect(recorder.model.arrivalCount == 1)
        #expect(recorder.model.glowCount == 1)
        #expect(recorder.glowingIDs == [nil, id, nil])
        #expect(recorder.durations == [.milliseconds(680), .milliseconds(720), .milliseconds(1180)])
    }

    @Test("AC-10: isAnimated が true でも、行以外の目的地では印のきっかけは進まない")
    func playWithMotionOnNonRowDoesNotAdvanceGlowCount() async {
        let recorder = Recorder()

        await recorder.model.play(text: "memo", destination: .draftsTab)

        #expect(recorder.model.glowCount == 0)
        #expect(recorder.model.arrivalCount == 1)
    }
}
