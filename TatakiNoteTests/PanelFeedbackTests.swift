import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct PanelFeedbackTests {
    @MainActor
    private final class Fixture {
        let temp: TemporaryDefaults
        let settings: AppSettings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        let model = PanelModel()
        let library = DraftLibrary(store: .inMemory)
        let session: DraftSession
        let sidebarModel: SidebarModel
        let saveAnimation: SaveAnimationModel
        let shaker = PanelShakerSpy()
        let beepSpy = BeepSpy()
        let feedback: PanelFeedback
        private let sleeper = HeldSleeper()

        init(isAnimationEnabled: Bool, isPresented: Bool = true) throws {
            temp = try TemporaryDefaults()
            settings = temp.makeSettings()
            settings.animationMode = isAnimationEnabled ? .on : .off
            settings.isSidebarOpen = false
            session = DraftSession(panel: model, library: library, ownProcessIdentifier: 4242)
            sidebarModel = SidebarModel(settings: settings, library: library, session: session)
            let sleeper = sleeper
            saveAnimation = SaveAnimationModel(sleep: { await sleeper.sleep($0) }, announce: { _ in })
            feedback = PanelFeedback(
                panel: window,
                model: model,
                session: session,
                sidebarModel: sidebarModel,
                library: library,
                saveAnimation: saveAnimation,
                settings: settings,
                shaker: shaker,
                beep: beepSpy.beep
            )
            if isPresented {
                model.present(target: nil)
            }
            feedback.startObserving()
        }

        func cleanup() {
            sleeper.releaseAll()
            temp.remove()
        }

        func settleObservation() async throws {
            try await Task.sleep(for: .milliseconds(100))
        }

        func pollUntil(_ condition: () -> Bool) async throws {
            try await waitUntil(attempts: 200, interval: .milliseconds(25), condition)
        }
    }

    // MARK: - 空の知らせ

    @Test("AC-6: アニメーションがオンで動きが落ち着いているときの空の知らせは、揺れだけでビープは鳴らない")
    func emptyInputShakesWhenShown() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }

        fixture.feedback.signalEmptyInput(motionPhase: .shown)

        #expect(fixture.shaker.shakeCount == 1)
        #expect(fixture.beepSpy.count == 0)
    }

    @Test("AC-6: アニメーションがオンでも、開く・閉じる動きの途中の空の知らせは何もしない", arguments: [PanelMotionPhase.opening, .closing, .hidden])
    func emptyInputDoesNothingDuringMotion(phase: PanelMotionPhase) throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }

        fixture.feedback.signalEmptyInput(motionPhase: phase)

        #expect(fixture.shaker.shakeCount == 0)
        #expect(fixture.beepSpy.count == 0)
    }

    @Test("AC-6: アニメーションがオフのときの空の知らせは、動きの段階に関わらずビープだけで揺れない", arguments: [PanelMotionPhase.shown, .opening, .closing])
    func emptyInputBeepsWhenAnimationIsOff(phase: PanelMotionPhase) throws {
        let fixture = try Fixture(isAnimationEnabled: false)
        defer { fixture.cleanup() }

        fixture.feedback.signalEmptyInput(motionPhase: phase)

        #expect(fixture.beepSpy.count == 1)
        #expect(fixture.shaker.shakeCount == 0)
    }

    // MARK: - 揺れ・保存の動きを止める

    @Test("AC-6: stopShaking は揺れを止める")
    func stopShakingStopsShaker() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }

        fixture.feedback.stopShaking()

        #expect(fixture.shaker.stopCount == 1)
    }

    @Test("AC-6: stopEffects は揺れを止め、出ているトーストを消す")
    func stopEffectsStopsShakerAndCancelsAnimation() async throws {
        let fixture = try Fixture(isAnimationEnabled: false)
        defer { fixture.cleanup() }
        fixture.feedback.showToast("お知らせ", style: .notice)
        try await fixture.pollUntil { fixture.saveAnimation.toastMessage != nil }
        #expect(fixture.saveAnimation.toastMessage == "お知らせ")
        #expect(fixture.saveAnimation.toastStyle == .notice)

        fixture.feedback.stopEffects()

        #expect(fixture.shaker.stopCount == 1)
        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(fixture.saveAnimation.phase == .idle)
    }

    // MARK: - 保存の動き・トースト

    @Test("AC-6: パネルが開いているとき、下書きに保存すると保存の動きとトーストが出る")
    func savingPlaysAnimationWhilePresented() async throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }
        fixture.model.text = "memo"

        fixture.session.saveCurrent()
        try await fixture.pollUntil { fixture.saveAnimation.playCount == 1 }

        #expect(fixture.saveAnimation.playCount == 1)
        #expect(fixture.saveAnimation.toastMessage == nil)
        let isFlying: Bool
        if case .flying = fixture.saveAnimation.phase {
            isFlying = true
        } else {
            isFlying = false
        }
        #expect(isFlying)
    }

    @Test("AC-6: パネルが開いていて書きかけを履歴へ移すと、履歴に残したトーストが出る")
    func archivingShowsToastWhilePresented() async throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.session.request(.newScratch)
        try await fixture.pollUntil { fixture.saveAnimation.toastMessage != nil }

        #expect(fixture.session.archivedScratchCount == 1)
        #expect(fixture.saveAnimation.toastMessage == SaveAnimationModel.archivedMessage)
    }

    @Test("AC-6: パネルが閉じているときは、下書きを保存しても保存の動きもトーストも出さない")
    func savingShowsNothingWhileHidden() async throws {
        let fixture = try Fixture(isAnimationEnabled: true, isPresented: false)
        defer { fixture.cleanup() }
        fixture.model.text = "memo"

        fixture.session.saveCurrent()
        try await fixture.settleObservation()

        #expect(fixture.session.lastSaveEvent != nil)
        #expect(fixture.saveAnimation.playCount == 0)
        #expect(fixture.saveAnimation.phase == .idle)
        #expect(fixture.saveAnimation.toastMessage == nil)
    }

    @Test("AC-6: パネルが閉じているときは、書きかけを履歴へ移してもトーストを出さない")
    func archivingShowsNothingWhileHidden() async throws {
        let fixture = try Fixture(isAnimationEnabled: true, isPresented: false)
        defer { fixture.cleanup() }
        fixture.model.text = "abc"

        fixture.session.request(.newScratch)
        try await fixture.settleObservation()

        #expect(fixture.session.archivedScratchCount == 1)
        #expect(fixture.saveAnimation.toastCount == 0)
        #expect(fixture.saveAnimation.toastMessage == nil)
    }
}
