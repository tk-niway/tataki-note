import AppKit
import Testing
@testable import TatakiNote

@MainActor
struct PanelControllerDismissTests {
    enum Entry: CaseIterable, Sendable {
        case close
        case closeImmediately
        case hideKey
    }

    @MainActor
    private final class Fixture {
        let defaults: TemporaryDefaults
        let controller: PanelController
        let animator = FakePanelFrameAnimator()
        let shaker = PanelShakerSpy()
        let hides = HideApplicationCounter()
        let library = DraftLibrary(store: .inMemory)
        let sleeper = HeldSleeper()
        let saveAnimation: SaveAnimationModel

        init(isAnimationEnabled: Bool) throws {
            defaults = try TemporaryDefaults()
            let settings = AppSettings(store: SettingsStore(defaults: defaults.defaults), reducesMotion: { false })
            settings.panelScreen = .main
            settings.animationMode = isAnimationEnabled ? .on : .off
            let sleeper = sleeper
            saveAnimation = SaveAnimationModel(sleep: { await sleeper.sleep($0) }, announce: { _ in })
            let hides = hides
            controller = PanelControllerFactory.make(
                settings: settings,
                library: library,
                saveAnimation: saveAnimation,
                animator: animator,
                shaker: shaker,
                hideApplication: { hides.record() }
            )
        }

        func openAndSettle() {
            controller.openWithoutTarget()
            if let last = animator.calls.indices.last {
                animator.finish(last)
            }
        }

        func leaveUnsavedWork() throws -> Task<Void, Never> {
            let draft = try #require(library.addDraft(text: "a"))
            library.updateDraft(id: draft.id, text: "ab")
            let animation = saveAnimation
            let toast = Task { await animation.showToast("書き出しました") }
            return toast
        }

        func cleanUp() {
            sleeper.releaseAll()
            controller.panel.orderOut(nil)
            for call in animator.calls {
                call.window.orderOut(nil)
            }
            defaults.remove()
        }

        func dismiss(_ entry: Entry) -> Bool {
            switch entry {
            case .close:
                controller.close()
                return true
            case .closeImmediately:
                controller.closeImmediately()
                return true
            case .hideKey:
                return controller.handleHideKey()
            }
        }
    }

    @Test("AC-5: 閉じる3つの入口は、揺れを止め、保存の動きを取り消し、パネルを閉じた状態にし、下書きを書き出す", arguments: Entry.allCases)
    func everyEntryStopsEffectsAndClosesPanel(entry: Entry) async throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanUp() }
        fixture.openAndSettle()
        let toast = try fixture.leaveUnsavedWork()
        await yieldUntil { fixture.saveAnimation.toastMessage != nil }
        #expect(fixture.saveAnimation.toastMessage != nil)
        #expect(fixture.library.hasPendingWrite)
        #expect(fixture.controller.model.isPresented)
        let stopsBefore = fixture.shaker.stopCount

        let handled = fixture.dismiss(entry)

        #expect(handled)
        #expect(fixture.shaker.stopCount == stopsBefore + 1)
        #expect(fixture.saveAnimation.toastMessage == nil)
        #expect(fixture.controller.model.isPresented == false)
        #expect(fixture.controller.panel.isVisible == false)
        #expect(fixture.library.hasPendingWrite == false)

        fixture.sleeper.releaseAll()
        await toast.value
    }

    @Test("AC-5: ⌘H は、閉じる動きが終わってからアプリを1回だけ隠す")
    func hideKeyHidesApplicationOnceAfterClosingMotion() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanUp() }
        fixture.openAndSettle()

        let handled = fixture.controller.handleHideKey()

        #expect(handled)
        #expect(fixture.animator.calls.count == 2)
        #expect(fixture.hides.count == 0)

        fixture.animator.finish(1)

        #expect(fixture.hides.count == 1)

        fixture.animator.finish(1)

        #expect(fixture.hides.count == 1)
    }

    @Test("AC-5: ⌘H の後すぐ開き直すと、アプリを隠さない")
    func reopeningAfterHideKeyDoesNotHideApplication() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanUp() }
        fixture.openAndSettle()
        #expect(fixture.controller.handleHideKey())

        fixture.controller.openWithoutTarget()
        fixture.animator.finish(1, moving: false)

        #expect(fixture.hides.count == 0)
        #expect(fixture.controller.model.isPresented)
    }

    @Test("AC-5: アニメーションがオフなら、⌘H は何もせず false を返す")
    func hideKeyReturnsFalseWhenAnimationIsOff() throws {
        let fixture = try Fixture(isAnimationEnabled: false)
        defer { fixture.cleanUp() }
        fixture.openAndSettle()
        let stopsBefore = fixture.shaker.stopCount

        let handled = fixture.controller.handleHideKey()

        #expect(handled == false)
        #expect(fixture.hides.count == 0)
        #expect(fixture.shaker.stopCount == stopsBefore)
        #expect(fixture.controller.model.isPresented)
        #expect(fixture.controller.panel.isVisible)
    }

    @Test("AC-5: パネルが開いていないときは、⌘H は何もせず false を返す")
    func hideKeyReturnsFalseWhenPanelIsNotShown() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanUp() }

        let handled = fixture.controller.handleHideKey()

        #expect(handled == false)
        #expect(fixture.hides.count == 0)
        #expect(fixture.animator.calls.isEmpty)
    }

    @Test("AC-5: アプリが隠れたときは、動きなしで閉じる")
    func closeImmediatelyClosesWithoutMotion() throws {
        let fixture = try Fixture(isAnimationEnabled: true)
        defer { fixture.cleanUp() }
        fixture.openAndSettle()

        fixture.controller.closeImmediately()

        #expect(fixture.animator.calls.count == 1)
        #expect(fixture.hides.count == 0)
        #expect(fixture.controller.model.isPresented == false)
        #expect(fixture.controller.panel.isVisible == false)
    }
}
