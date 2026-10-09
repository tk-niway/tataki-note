import ApplicationServices
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct NoteModeAutoShowTests {
    private let fieldE = AXUIElementCreateApplication(pid_t.max)

    @Test("AC-17: ノートモードでは、入力欄が選ばれてもクリックされてもパネルを自動で開かない")
    func noteModeDoesNotAutoShow() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.selectAppMode(.note, hotkey: nil)

        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()

        #expect(fixture.showCount == 0)
        #expect(fixture.probe.targets.isEmpty)
    }

    @Test("AC-17: ノートモードでは、前面になったアプリのフォーカスの見張り・クリックの見張り・Web の中身を出す頼みをしない")
    func noteModeDoesNotStartWatching() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.selectAppMode(.note, hotkey: nil)

        fixture.activate(WatcherFixture.editor)

        #expect(fixture.environment.clickMonitorsAdded == 0)
        #expect(fixture.environment.activeClickMonitorCount == 0)
        #expect(fixture.environment.exposedTargets.isEmpty)
    }

    @Test("AC-17: 見張っているあいだにノートモードにすると見張りをやめ、パネルを自動で開かない")
    func switchingToNoteModeStopsWatching() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        #expect(fixture.environment.activeClickMonitorCount == 1)

        fixture.settings.selectAppMode(.note, hotkey: nil)
        fixture.watcher.applyAppMode()

        #expect(fixture.environment.activeClickMonitorCount == 0)
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        fixture.watcher.handleClick()
        #expect(fixture.showCount == 0)
    }

    @Test("AC-17: ノートモードにしても自動表示の保存値は書き換えず、インサートモードに戻すと前面のアプリの見張りを掛け直して自動表示する")
    func returningToInsertModeWatchesFrontmostApp() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)
        fixture.settings.selectAppMode(.note, hotkey: nil)
        fixture.watcher.applyAppMode()
        #expect(fixture.settings.autoShowMode == .allApps)
        #expect(fixture.environment.activeClickMonitorCount == 0)

        fixture.settings.selectAppMode(.insert, hotkey: nil)
        fixture.watcher.applyAppMode()

        #expect(fixture.environment.activeClickMonitorCount == 1)
        #expect(fixture.environment.exposedTargets == [WatcherFixture.editor, WatcherFixture.editor])
        fixture.focusTextField(fieldE)
        fixture.watcher.handleFocusChanged()
        #expect(fixture.showCount == 1)
    }

    @Test("AC-17: 何度掛け直しても、クリックの見張りは1つだけ")
    func repeatedApplyKeepsSingleClickMonitor() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(WatcherFixture.editor)

        fixture.watcher.applyAppMode()
        fixture.watcher.applyAppMode()
        fixture.watcher.applyAppMode()

        let environment = fixture.environment
        #expect(environment.clickMonitorsAdded - environment.clickMonitorsRemoved == 1)
        #expect(environment.activeClickMonitorCount == 1)
    }

    @Test("AC-17: ノートモードで閉じたあとの入力欄のクリックの抑えは残らず、閉じても入力欄を調べない")
    func noteModeDismissalDoesNotProbe() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.settings.selectAppMode(.note, hotkey: nil)
        fixture.activate(WatcherFixture.editor)
        fixture.focusTextField(fieldE)

        fixture.dismissAndWait(.cancelled)

        #expect(fixture.probe.targets.isEmpty)
        #expect(!fixture.watcher.isSuppressingClicks)
    }

    @Test("AC-17: 見張りの掛け直しは、前面のアプリが無ければ何も掛けない")
    func applyWithoutFrontmostAppWatchesNothing() throws {
        let fixture = try WatcherFixture()
        defer { fixture.removeSuite() }
        fixture.activate(nil)

        fixture.watcher.applyAppMode()

        #expect(fixture.environment.clickMonitorsAdded == 0)
        #expect(fixture.environment.exposedTargets.isEmpty)
    }
}
