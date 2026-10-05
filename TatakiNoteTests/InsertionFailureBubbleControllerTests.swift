import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
final class AnchorLocatorStub: StatusItemAnchorLocating {
    var results: [NSView?] = []
    var fallback: NSView?
    private(set) var callCount = 0

    func locateAnchor() -> NSView? {
        callCount += 1
        if !results.isEmpty {
            return results.removeFirst()
        }
        return fallback
    }
}

@MainActor
final class BubblePresenterStub: InsertionFailureBubblePresenting {
    struct Shown {
        var message: String
        var anchor: NSView
    }

    var onClick: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var onClosedBySystem: (() -> Void)?
    private(set) var shown: [Shown] = []
    private(set) var closeCount = 0

    func show(message: String, relativeTo anchor: NSView) {
        shown.append(Shown(message: message, anchor: anchor))
    }

    func close() {
        closeCount += 1
    }
}

@MainActor
final class SleepStub {
    var suspendsSearchInterval = false
    private(set) var requested: [Duration] = []
    private var pending: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int { pending.count }

    func sleep(_ duration: Duration) async {
        requested.append(duration)
        if duration == InsertionFailureBubbleController.anchorSearchInterval && !suspendsSearchInterval {
            return
        }
        await withCheckedContinuation { pending.append($0) }
    }

    func resumeNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume()
    }

    func resumeAll() {
        while !pending.isEmpty {
            pending.removeFirst().resume()
        }
    }

    func waitUntilPending(_ count: Int) async {
        var spins = 0
        while pending.count < count && spins < 10_000 {
            await Task.yield()
            spins += 1
        }
    }
}

@MainActor
final class OpenPanelCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
struct BubbleHarness {
    let model = InsertionFailureBubbleModel()
    let locator = AnchorLocatorStub()
    let presenter = BubblePresenterStub()
    let sleeper = SleepStub()
    let openPanel = OpenPanelCounter()
    let controller: InsertionFailureBubbleController

    init() {
        let model = model
        let locator = locator
        let presenter = presenter
        let sleeper = sleeper
        let openPanel = openPanel
        controller = InsertionFailureBubbleController(
            model: model,
            locator: locator,
            presenter: presenter,
            sleep: { await sleeper.sleep($0) },
            onOpenPanel: { openPanel.increment() }
        )
    }
}

@MainActor
struct InsertionFailureBubbleControllerTests {
    private let notice = InsertionFailureNotice(reason: .noTarget, isDraftKept: true)

    private func makeSettings(name: String) throws -> (AppSettings, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: name))
        return (AppSettings(store: SettingsStore(defaults: defaults)), defaults)
    }

    // MARK: - AC-1

    @Test("AC-1: どの理由・下書きの状態で知らされても、見つけた出どころに同じ文の吹き出しが1つ出る")
    func showsOneBubbleForEveryNotice() async {
        let reasons: [InsertionFailureNotice.Reason] = [
            .noTarget,
            .targetNotActivated(appName: "メモ"),
            .targetNotActivated(appName: nil),
            .noTextInput(appName: "メモ"),
            .noTextInput(appName: nil),
        ]
        for reason in reasons {
            for isDraftKept in [true, false] {
                let harness = BubbleHarness()
                defer { harness.sleeper.resumeAll() }
                let anchor = NSView()
                harness.locator.fallback = anchor

                await harness.controller.notify(InsertionFailureNotice(reason: reason, isDraftKept: isDraftKept))

                #expect(harness.presenter.shown.count == 1)
                #expect(harness.presenter.shown.first?.message == InsertionFailureBubbleModel.message)
                #expect(harness.presenter.shown.first?.anchor === anchor)
                #expect(harness.model.isPresented == true)
            }
        }
    }

    // MARK: - AC-3

    @Test("AC-3: 吹き出しは5秒後に閉じ、一時的に出していたアイコンも消える。5秒より前には閉じない")
    func closesAfterFiveSeconds() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()

        await harness.controller.notify(notice)
        await harness.sleeper.waitUntilPending(1)

        #expect(harness.sleeper.requested == [.seconds(5)])
        #expect(harness.presenter.closeCount == 0)
        #expect(harness.model.isPresented == true)
        #expect(harness.model.isMenuBarIconInserted(isIconShownSetting: false) == true)

        harness.sleeper.resumeNext()
        await harness.controller.pendingDismissal?.value

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
        #expect(harness.model.isMenuBarIconInserted(isIconShownSetting: false) == false)
    }

    // MARK: - AC-4

    @Test("AC-4: 出している間にまた知らされると、吹き出しは出し直されて5秒を数え直し、前の5秒では閉じない")
    func secondFailureRestartsTimer() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()

        await harness.controller.notify(notice)
        await harness.sleeper.waitUntilPending(1)
        let firstDismissal = harness.controller.pendingDismissal
        await harness.controller.notify(notice)
        await harness.sleeper.waitUntilPending(2)

        #expect(harness.presenter.shown.count == 2)
        #expect(harness.presenter.closeCount == 0)
        #expect(harness.model.presentationID == 2)

        harness.sleeper.resumeNext()
        await firstDismissal?.value

        #expect(harness.presenter.closeCount == 0)
        #expect(harness.model.isPresented == true)

        harness.sleeper.resumeNext()
        await harness.controller.pendingDismissal?.value

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
    }

    // MARK: - AC-5

    @Test("AC-5: 吹き出しをクリックすると吹き出しが閉じて、パネルを開く処理が1回呼ばれる")
    func clickClosesBubbleAndOpensPanel() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)

        harness.presenter.onClick?()

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
        #expect(harness.openPanel.count == 1)
    }

    // MARK: - AC-6

    @Test("AC-6: 吹き出しの外をクリックすると、5秒を待たずに閉じ、パネルは開かない")
    func outsideClickClosesWithoutOpeningPanel() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)

        harness.presenter.onOutsideClick?()

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
        #expect(harness.openPanel.count == 0)
    }

    @Test("AC-6: システムが吹き出しを閉じたときも、5秒を待たずに閉じ、パネルは開かない")
    func systemCloseClosesWithoutOpeningPanel() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)

        harness.presenter.onClosedBySystem?()

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
        #expect(harness.openPanel.count == 0)
    }

    @Test("AC-6: 閉じた後に5秒が来ても、もう一度閉じることはしない")
    func expiryAfterManualCloseDoesNothing() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)
        await harness.sleeper.waitUntilPending(1)

        harness.presenter.onOutsideClick?()
        harness.sleeper.resumeNext()
        await harness.controller.pendingDismissal?.value

        #expect(harness.presenter.closeCount == 1)
    }

    // MARK: - AC-8

    @Test("AC-8: 吹き出しを出している間に利用者がアイコンを外すと、アイコンを隠す設定がオンになり吹き出しが閉じる")
    func iconRemovalClosesBubble() async throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)

        harness.controller.menuBarIconInsertionDidChange(to: false, settings: settings)

        #expect(harness.presenter.closeCount == 1)
        #expect(harness.model.isPresented == false)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
    }

    @Test("AC-8: 吹き出しのために一時的に出している間に出すが書き戻されても、吹き出しは閉じず、アイコンを隠す設定はオンのまま")
    func writeBackWhilePresentedKeepsBubbleAndHiddenSetting() async throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        settings.hidesMenuBarIcon = true
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)

        harness.controller.menuBarIconInsertionDidChange(to: true, settings: settings)

        #expect(harness.presenter.closeCount == 0)
        #expect(harness.model.isPresented == true)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
    }

    @Test("AC-8: 吹き出しを出していないときにアイコンが外されても、閉じるものは無く、アイコンを隠す設定がオンになる")
    func iconRemovalWithoutBubbleOnlyHidesIcon() async throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let harness = BubbleHarness()

        harness.controller.menuBarIconInsertionDidChange(to: false, settings: settings)

        #expect(harness.presenter.closeCount == 0)
        #expect(settings.hidesMenuBarIcon == true)
    }

    // MARK: - AC-9

    @Test("AC-9: 出どころが見つからないときは、50ms ずつ空けて21回探し、吹き出しを出さずに一時的なアイコンを戻す")
    func givesUpWhenAnchorNeverFound() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }

        await harness.controller.notify(notice)

        #expect(harness.locator.callCount == 1 + InsertionFailureBubbleController.anchorSearchAttempts)
        #expect(harness.sleeper.requested.count == InsertionFailureBubbleController.anchorSearchAttempts)
        #expect(harness.sleeper.requested.allSatisfy { $0 == .milliseconds(50) })
        #expect(harness.presenter.shown.isEmpty)
        #expect(harness.model.isPresented == false)
        #expect(harness.model.isMenuBarIconInserted(isIconShownSetting: false) == false)
        #expect(harness.controller.pendingDismissal == nil)
    }

    @Test("AC-9: 途中で出どころが見つかれば、そこで吹き出しを出す")
    func showsWhenAnchorFoundDuringSearch() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        let anchor = NSView()
        harness.locator.results = [nil, nil, anchor]

        await harness.controller.notify(notice)

        #expect(harness.locator.callCount == 3)
        #expect(harness.sleeper.requested.filter { $0 == .milliseconds(50) }.count == 2)
        #expect(harness.presenter.shown.count == 1)
        #expect(harness.presenter.shown.first?.anchor === anchor)
        #expect(harness.model.isPresented == true)
    }

    @Test("AC-9: 探している間に次の失敗が来たら、前の探しは吹き出しを出さずに終わる")
    func supersededSearchDoesNothing() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.sleeper.suspendsSearchInterval = true
        let first = Task { await harness.controller.notify(notice) }
        await harness.sleeper.waitUntilPending(1)

        harness.sleeper.suspendsSearchInterval = false
        harness.locator.fallback = NSView()
        await harness.controller.notify(notice)
        #expect(harness.presenter.shown.count == 1)

        harness.sleeper.resumeNext()
        await first.value

        #expect(harness.presenter.shown.count == 1)
        #expect(harness.locator.callCount == 2)
        #expect(harness.model.isPresented == true)
    }

    @Test("AC-9: 探している間に吹き出しが閉じられたら、後から吹き出しを出さない")
    func dismissedSearchDoesNotShow() async {
        let harness = BubbleHarness()
        defer { harness.sleeper.resumeAll() }
        harness.sleeper.suspendsSearchInterval = true
        let search = Task { await harness.controller.notify(notice) }
        await harness.sleeper.waitUntilPending(1)

        harness.controller.dismiss()
        harness.locator.fallback = NSView()
        harness.sleeper.resumeNext()
        await search.value

        #expect(harness.presenter.shown.isEmpty)
        #expect(harness.model.isPresented == false)
        #expect(harness.controller.pendingDismissal == nil)
    }
}
