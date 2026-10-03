import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AutoShowClickSuppressionTests {
    private let fieldE = AXUIElementCreateApplication(pid_t.max)
    private let fieldF = AXUIElementCreateApplication(4_242)
    private let otherElement = AXUIElementCreateSystemWide()

    private let frameContainingClick = CGRect(x: 50, y: 80, width: 200, height: 40)

    private func makeFixture(isTrusted: Bool = true) throws -> WatcherFixture {
        let fixture = try WatcherFixture(isTrusted: isTrusted)
        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        return fixture
    }

    private func cancelPanel(_ fixture: WatcherFixture) {
        fixture.watcher.handlePanelDismissed(.cancelled, panelTarget: WatcherFixture.editor)
    }

    @Test("AC-3: 挿入せずに閉じたあと、閉じたときに選ばれていた入力欄の枠の中を続けてクリックしても出さない")
    func clickAfterCancelDoesNotShow() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        #expect(fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()
        fixture.watcher.handleClick()
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)

        fixture.advance(by: FocusedElementWatcher.dismissGrace + 0.5)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)
    }

    @Test("AC-4: 確定で閉じたあとは、同じ入力欄の枠の中をクリックすると閉じた直後でも出す")
    func clickAfterCommitShows() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        fixture.watcher.handlePanelDismissed(.committed, panelTarget: WatcherFixture.editor)
        #expect(!fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 1)
    }

    @Test("AC-5: 抑えている間に同じアプリの別のボタンが選ばれると抑えが解け、元の入力欄の枠の中をクリックすると出す")
    func focusingButtonReleasesSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.focusButton(otherElement)
        fixture.watcher.handleFocusChanged()
        #expect(!fixture.watcher.isSuppressingClicks)

        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-5: 抑えている間に同じアプリの別の入力欄が選ばれると抑えが解け、元の入力欄の枠の中をクリックすると出す")
    func focusingOtherFieldReleasesSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.focusTextField(fieldF, frame: frameContainingClick)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 0)
        #expect(!fixture.watcher.isSuppressingClicks)

        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-5: 同じ入力欄へのフォーカスの通知では抑えが解けない")
    func focusNotificationForSameFieldKeepsSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 0)
        #expect(fixture.watcher.isSuppressingClicks)

        fixture.advance(by: FocusedElementWatcher.dismissGrace)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)
    }

    @Test("AC-6: 抑えている間に別のアプリが前面になると抑えが解け、元のアプリに戻ったあとクリックすると出す")
    func switchingAppReleasesSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.activate(WatcherFixture.otherApp)
        #expect(!fixture.watcher.isSuppressingClicks)
        fixture.activate(WatcherFixture.editor)
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 1)
    }

    @Test("AC-6: 同じアプリが前面になり直しただけでは抑えが解けない")
    func reactivatingSameAppKeepsSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 0)
    }

    @Test("AC-6: 前面のアプリが分からなくなったときも抑えが解ける")
    func unknownFrontmostReleasesSuppression() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.activate(nil)

        #expect(!fixture.watcher.isSuppressingClicks)
    }

    @Test("AC-7: 挿入せずに閉じてから 30 秒たつと同じ入力欄の枠の中のクリックで出し、30 秒より前は出さない")
    func suppressionExpiresAfterThirtySeconds() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.advance(by: FocusedElementWatcher.clickSuppressionDuration - 0.1)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)

        fixture.advance(by: 0.2)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)
        #expect(!fixture.watcher.isSuppressingClicks)
    }

    @Test("AC-8: 抑えている間でも、閉じたときに選ばれていたものと違う入力欄の枠の中をクリックしたときはフォーカスの通知が届く前でも出す")
    func clickOnOtherFieldBeforeFocusNotificationShows() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.focusTextField(fieldF, frame: frameContainingClick)
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 1)
    }

    @Test("AC-9: 閉じたパネルの挿入先が見張っているアプリと違うとき、または挿入先が無いときは抑えない")
    func differentOrMissingPanelTargetDoesNotSuppress() throws {
        let panelTargets: [InsertionTarget?] = [WatcherFixture.otherApp, nil]
        for panelTarget in panelTargets {
            let fixture = try makeFixture()
            defer { fixture.removeSuite() }

            fixture.watcher.handlePanelDismissed(.cancelled, panelTarget: panelTarget)
            #expect(!fixture.watcher.isSuppressingClicks, "\(String(describing: panelTarget))")
            fixture.watcher.handleClick()

            #expect(fixture.showCount == 1, "\(String(describing: panelTarget))")
        }
    }

    @Test("AC-9: 選ばれている要素が分からないときは抑えない")
    func unknownFocusedElementDoesNotSuppress() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }
        fixture.probe.result = FocusedElementProbe(element: nil, lookup: .noFocusedElement, frame: nil)

        cancelPanel(fixture)
        #expect(!fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)

        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-9: 見張っていないアプリでは抑えず、フォーカスのある要素も問い合わせない")
    func unwatchedAppsAreNeitherSuppressedNorProbed() throws {
        let ownApp = InsertionTarget(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: "com.example.TatakiNote",
            localizedName: "TatakiNote"
        )
        let cases: [(label: String, isTrusted: Bool, mode: AutoShowMode, apps: [AutoShowApp], target: InsertionTarget)] = [
            ("off", true, .off, [], WatcherFixture.editor),
            ("not listed", true, .selectedApps, [WatcherFixture.otherAutoShowApp], WatcherFixture.editor),
            ("own app", true, .allApps, [], ownApp),
            ("untrusted", false, .allApps, [], WatcherFixture.editor),
        ]
        for testCase in cases {
            let fixture = try WatcherFixture(isTrusted: testCase.isTrusted)
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = testCase.mode
            fixture.settings.autoShowApps = testCase.apps
            fixture.activate(testCase.target)
            fixture.focusTextField(fieldE, frame: frameContainingClick)
            let probeCount = fixture.probe.targets.count

            fixture.watcher.handlePanelDismissed(.cancelled, panelTarget: testCase.target)

            #expect(!fixture.watcher.isSuppressingClicks, "\(testCase.label)")
            #expect(fixture.probe.targets.count == probeCount, "\(testCase.label)")
        }
    }

    @Test("AC-10: 抑えている間も、閉じた直後は別の入力欄へのフォーカスの移動で出さず、過ぎると出す")
    func focusChangeToOtherFieldFollowsDismissGrace() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        cancelPanel(fixture)
        fixture.focusTextField(fieldF)
        fixture.advance(by: FocusedElementWatcher.dismissGrace / 2)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 0)

        fixture.advance(by: FocusedElementWatcher.dismissGrace)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-10: 抑えている間も、同じ入力欄へ当て直されただけでは出さない")
    func focusNotificationForShownFieldDoesNotShowAgain() throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)

        cancelPanel(fixture)
        fixture.advance(by: FocusedElementWatcher.dismissGrace + 0.01)
        fixture.watcher.handleFocusChanged()

        #expect(fixture.showCount == 1)
    }

    @Test("AC-11: パネルを dismiss() で閉じると同じ入力欄のクリックで出さず、prepareCommit で閉じると出す")
    func panelStateReachesWatcher() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeSuite() }

        let firstDismissal = fixture.environment.now
        fixture.panelModel.present(target: WatcherFixture.editor)
        await settle()
        fixture.panelModel.dismiss()
        await yieldUntil { fixture.watcher.panelDismissedAt == firstDismissal }
        #expect(fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)

        fixture.advance(by: 10)
        let secondDismissal = fixture.environment.now
        fixture.panelModel.present(target: WatcherFixture.editor)
        await settle()
        fixture.panelModel.text = "x"
        _ = fixture.panelModel.prepareCommit(isAccessibilityTrusted: true)
        await yieldUntil { fixture.watcher.panelDismissedAt == secondDismissal }
        #expect(!fixture.watcher.isSuppressingClicks)
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 1)
    }

    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
