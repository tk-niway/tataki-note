import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct FocusedElementWatcherQueryTests {
    private let fieldE = AXUIElementCreateApplication(pid_t.max)
    private let frameContainingClick = CGRect(x: 50, y: 80, width: 200, height: 40)

    @Test("AC-12: クリックで出すときは、調べたアプリのプロセス番号と、要素・種類・枠つきの結果をそのまま開く側に渡す")
    func clickPassesProbeWithFrame() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)

        fixture.environment.fireClick()

        #expect(fixture.showCount == 1)
        let focus = try #require(fixture.environment.shownFocuses.first)
        #expect(focus.processIdentifier == WatcherFixture.editor.processIdentifier)
        #expect(focus.probe.element.map { CFEqual($0, fieldE) } == true)
        #expect(FocusedTextInputState.classify(focus.probe.lookup) == .textInput)
        #expect(focus.probe.frame == frameContainingClick)
        #expect(fixture.probe.targets == [WatcherFixture.editor])
        #expect(fixture.probe.readsFrameValues == [true])
    }

    @Test("AC-12: フォーカスの移動で出すときは、調べたアプリのプロセス番号と、枠なしの結果をそのまま開く側に渡す")
    func focusChangePassesProbeWithoutFrame() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)

        fixture.watcher.handleFocusChanged()

        #expect(fixture.showCount == 1)
        let focus = try #require(fixture.environment.shownFocuses.first)
        #expect(focus.processIdentifier == WatcherFixture.editor.processIdentifier)
        #expect(focus.probe.element.map { CFEqual($0, fieldE) } == true)
        #expect(FocusedTextInputState.classify(focus.probe.lookup) == .textInput)
        #expect(focus.probe.frame == nil)
        #expect(fixture.probe.readsFrameValues == [false])
    }

    @Test("AC-13: 自動表示が「オフ」のとき、見張らないアプリが前面のとき、前面が分からないときは、クリックを見張らない")
    func unwatchedAppsAddNoClickMonitor() throws {
        let unwatched: [(mode: AutoShowMode, apps: [AutoShowApp], target: InsertionTarget?)] = [
            (.off, [WatcherFixture.editorApp], WatcherFixture.editor),
            (.selectedApps, [WatcherFixture.otherAutoShowApp], WatcherFixture.editor),
            (.selectedApps, [], WatcherFixture.editor),
            (.selectedApps, [WatcherFixture.editorApp], InsertionTarget(processIdentifier: pid_t.max, bundleIdentifier: nil)),
            (.allApps, [], nil),
            (.allApps, [], InsertionTarget(processIdentifier: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: "com.example.TatakiNote")),
        ]
        for (mode, apps, target) in unwatched {
            let fixture = try WatcherFixture()
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = mode
            fixture.settings.autoShowApps = apps

            fixture.activate(target)
            fixture.focusTextField(fieldE, frame: frameContainingClick)
            fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
            fixture.environment.fireClick()

            let label = "\(mode) \(apps.map { $0.bundleIdentifier }) \(String(describing: target))"
            #expect(fixture.environment.clickMonitorsAdded == 0, "\(label)")
            #expect(fixture.environment.activeClickMonitorCount == 0, "\(label)")
            #expect(fixture.showCount == 0, "\(label)")
        }
    }

    @Test("AC-13: 許可が無いときは、クリックを見張らない")
    func untrustedAddsNoClickMonitor() throws {
        let fixture = try WatcherFixture(isTrusted: false)
        defer { fixture.removeSuite() }

        fixture.activate(WatcherFixture.editor)

        #expect(fixture.environment.clickMonitorsAdded == 0)
        #expect(fixture.environment.activeClickMonitorCount == 0)
    }

    @Test("AC-13: 見張るアプリ(「全アプリ」・「選んだアプリのみ」で選んだアプリ)が前面のときは、クリックを見張る")
    func watchedAppsAddClickMonitor() throws {
        let watched: [(mode: AutoShowMode, apps: [AutoShowApp])] = [
            (.allApps, []),
            (.selectedApps, [WatcherFixture.editorApp]),
        ]
        for (mode, apps) in watched {
            let fixture = try WatcherFixture()
            defer { fixture.removeSuite() }
            fixture.settings.autoShowMode = mode
            fixture.settings.autoShowApps = apps

            fixture.activate(WatcherFixture.editor)

            #expect(fixture.environment.clickMonitorsAdded == 1, "\(mode)")
            #expect(fixture.environment.activeClickMonitorCount == 1, "\(mode)")
        }
    }

    @Test("AC-14: 「オフ」から「全アプリ」に変えても、次にアプリが前面になるまではクリックを見張らず、前面になったところから見張る")
    func switchingOffToAllAppsTakesEffectOnNextActivation() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.autoShowMode = .off
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.activeClickMonitorCount == 0)

        fixture.settings.autoShowMode = .allApps
        #expect(fixture.environment.clickMonitorsAdded == 0)
        #expect(fixture.environment.activeClickMonitorCount == 0)

        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.clickMonitorsAdded == 1)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.environment.fireClick()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-14: 見張るアプリから見張らないアプリが前面になったときは、クリックの見張りを外す")
    func switchingToUnwatchedAppRemovesClickMonitor() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.autoShowMode = .selectedApps
        fixture.settings.autoShowApps = [WatcherFixture.editorApp]
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        fixture.activate(WatcherFixture.otherApp)

        #expect(fixture.environment.activeClickMonitorCount == 0)
        #expect(fixture.environment.clickMonitorsRemoved == 1)
        fixture.focusTextField(fieldE, frame: frameContainingClick)
        fixture.environment.mouseLocation = CGPoint(x: 100, y: 700)
        fixture.environment.fireClick()
        #expect(fixture.showCount == 0)
    }

    @Test("AC-14: 見張るアプリが続けて前面になっても、付いているクリックの見張りは常に1つまで")
    func atMostOneClickMonitorStaysAttached() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }

        for _ in 0..<3 {
            fixture.activate(WatcherFixture.editor)
            #expect(fixture.environment.activeClickMonitorCount == 1)
        }
        fixture.activate(WatcherFixture.otherApp)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        #expect(fixture.environment.clickMonitorsAdded == 4)
        #expect(fixture.environment.clickMonitorsRemoved == 3)
    }

    @Test("AC-14: 見張りを止めたときは、クリックの見張りを外す")
    func stopRemovesClickMonitor() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        fixture.watcher.stop()

        #expect(fixture.environment.activeClickMonitorCount == 0)
        #expect(fixture.environment.clickMonitorsRemoved == 1)
    }
}
