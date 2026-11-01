import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class TestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
private struct Fixture {
    let temporary: TemporaryDefaults
    let settings: AppSettings
    let updater: RecordingUpdater
    let clock: TestClock
    let model: UpdateModel

    init() throws {
        temporary = try TemporaryDefaults()
        settings = temporary.makeSettings()
        updater = RecordingUpdater()
        clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let clock = self.clock
        model = UpdateModel(settings: settings, updater: updater, now: { clock.date })
    }

    func remove() {
        temporary.remove()
    }
}

@MainActor
struct UpdateModelTests {
    private let day: TimeInterval = 24 * 60 * 60

    @Test("AC-3: オフラインの間は、きっかけが来ても確認を始めず、印も出ない")
    func offlineDoesNotCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.evaluate()
        fixture.model.networkDidChange(isOnline: false)
        fixture.model.evaluate()
        fixture.clock.date.addTimeInterval(3 * day)
        fixture.model.evaluate()

        #expect(fixture.updater.backgroundCheckCount == 0)
        #expect(fixture.model.pendingVersion == nil)
        #expect(!fixture.model.isUpdatePending)
    }

    @Test("AC-3: オンラインに戻ったとき、前回から24時間以上なら確認を始める")
    func returningOnlineChecksWhenDue() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.settings.lastUpdateCheckDate = fixture.clock.date.addingTimeInterval(-day)
        fixture.model.networkDidChange(isOnline: false)
        fixture.model.networkDidChange(isOnline: true)

        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-3: オンラインに戻ったとき、前回から24時間未満なら確認を始めない")
    func returningOnlineDoesNotCheckWhenRecent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.settings.lastUpdateCheckDate = fixture.clock.date.addingTimeInterval(-(day - 1))
        fixture.model.networkDidChange(isOnline: false)
        fixture.model.networkDidChange(isOnline: true)

        #expect(fixture.updater.backgroundCheckCount == 0)
    }

    @Test("AC-3: オンラインのままの知らせでは、確認を重ねて始めない")
    func repeatedOnlineNotificationDoesNotRecheckByItself() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.networkDidChange(isOnline: true)
        fixture.model.networkDidChange(isOnline: true)

        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-3: オンラインになったあとの1時間ごと・復帰のきっかけで、24時間を過ぎていれば確認を始める")
    func tickChecksWhenDueAfterOnline() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.settings.lastUpdateCheckDate = fixture.clock.date
        fixture.model.networkDidChange(isOnline: true)
        fixture.model.evaluate()
        #expect(fixture.updater.backgroundCheckCount == 0)

        fixture.clock.date.addTimeInterval(day)
        fixture.model.evaluate()
        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-4: 自動の確認がオフなら、時間がたってもオンラインに戻っても裏の確認を始めない")
    func disabledNeverChecksInBackground() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.isAutomaticCheckEnabled = false
        fixture.model.networkDidChange(isOnline: true)
        fixture.clock.date.addTimeInterval(3 * day)
        fixture.model.evaluate()
        fixture.model.networkDidChange(isOnline: false)
        fixture.model.networkDidChange(isOnline: true)

        #expect(fixture.updater.backgroundCheckCount == 0)
    }

    @Test("AC-4: 自動の確認がオフでも、手の確認は使える")
    func disabledStillAllowsUserCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.isAutomaticCheckEnabled = false
        fixture.model.checkByUser()

        #expect(fixture.updater.userCheckCount == 1)
        #expect(fixture.updater.backgroundCheckCount == 0)
    }

    @Test("AC-4: 自動の確認をオンに戻すと、その場で判定して確認を始める")
    func enablingEvaluatesImmediately() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.isAutomaticCheckEnabled = false
        fixture.model.networkDidChange(isOnline: true)
        #expect(fixture.updater.backgroundCheckCount == 0)

        fixture.model.isAutomaticCheckEnabled = true
        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-4: 自動の確認をオンに戻しても、前回から24時間たっていなければ確認を始めない")
    func enablingRespectsInterval() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.settings.lastUpdateCheckDate = fixture.clock.date
        fixture.model.isAutomaticCheckEnabled = false
        fixture.model.networkDidChange(isOnline: true)
        fixture.model.isAutomaticCheckEnabled = true

        #expect(fixture.updater.backgroundCheckCount == 0)
    }

    @Test("AC-5: 確認が済んだ(最新)ときに、前回の確認の日時を記録する")
    func completedCheckRecordsDate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(fixture.settings.lastUpdateCheckDate == nil)
        fixture.updater.send(.checkCompleted)

        #expect(fixture.settings.lastUpdateCheckDate == fixture.clock.date)
        #expect(fixture.temporary.makeSettings().lastUpdateCheckDate == fixture.clock.date)
    }

    @Test("AC-5: 新しいバージョンを見つけたときも、確認が済んだ日時を記録する")
    func foundUpdateRecordsDate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.checkCompleted)
        fixture.updater.send(.foundInBackground(version: "1.3.0"))

        #expect(fixture.settings.lastUpdateCheckDate == fixture.clock.date)
        #expect(fixture.model.pendingVersion == "1.3.0")
    }

    @Test("AC-5: 確認に失敗したときは、前回の確認の日時を記録しない")
    func failedCheckDoesNotRecordDate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.checkFailed)

        #expect(fixture.settings.lastUpdateCheckDate == nil)
        #expect(fixture.temporary.makeSettings().lastUpdateCheckDate == nil)
    }

    @Test("AC-5: 記録した日時から24時間たつまでは確認を始めず、たつと始める")
    func recordedDateGatesNextCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.networkDidChange(isOnline: true)
        #expect(fixture.updater.backgroundCheckCount == 1)

        fixture.updater.send(.checkCompleted)
        fixture.clock.date.addTimeInterval(day - 1)
        fixture.model.evaluate()
        #expect(fixture.updater.backgroundCheckCount == 1)

        fixture.clock.date.addTimeInterval(1)
        fixture.model.evaluate()
        #expect(fixture.updater.backgroundCheckCount == 2)
    }

    @Test("AC-5: 前回の確認の日時が壊れた値でも、次の判定で確認を始める")
    func brokenStoredDateStartsCheck() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        temporary.defaults.set("yesterday", forKey: SettingsStore.Key.lastUpdateCheckDate)
        let updater = RecordingUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)

        model.networkDidChange(isOnline: true)

        #expect(updater.backgroundCheckCount == 1)
    }

    @Test("AC-6: 裏の確認で新しいバージョンが見つかると、版の番号つきで「新しいバージョンあり」になる")
    func foundInBackgroundSetsPendingVersion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(fixture.model.menuTitleForPendingUpdate == nil)
        #expect(fixture.model.settingsStatusText == nil)

        fixture.updater.send(.foundInBackground(version: "1.3.0"))

        #expect(fixture.model.pendingVersion == "1.3.0")
        #expect(fixture.model.isUpdatePending)
        #expect(fixture.model.menuTitleForPendingUpdate == "新しいバージョンがあります(1.3.0)")
        #expect(fixture.model.settingsStatusText == "新しいバージョン 1.3.0 があります")
        #expect(fixture.model.badgedSettingsSections == [.appInfo])
    }

    @Test("AC-6: 裏の確認に失敗しても、利用者に何も出ない")
    func failedBackgroundCheckShowsNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.checkFailed)

        #expect(fixture.model.pendingVersion == nil)
        #expect(fixture.model.menuTitleForPendingUpdate == nil)
        #expect(fixture.model.settingsStatusText == nil)
        #expect(fixture.model.badgedSettingsSections.isEmpty)
        #expect(fixture.updater.userCheckCount == 0)
    }

    @Test("AC-6: 裏で見つけた更新をすぐ出さないと Sparkle に答え、控えめな知らせを使う")
    func presentationDoesNotShowBackgroundUpdateImmediately() {
        #expect(UpdatePresentation.showsBackgroundUpdateImmediately == false)
        #expect(UpdatePresentation.supportsGentleReminders == true)
    }

    @Test("AC-6: 新しいバージョンを見つけても、見つけただけでは手の確認(窓)を始めない")
    func foundInBackgroundDoesNotOpenWindow() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.foundInBackground(version: "1.3.0"))

        #expect(fixture.updater.userCheckCount == 0)
    }

    @Test("AC-6: 印があるうちは、きっかけが来ても裏の確認を重ねない")
    func pendingUpdateBlocksBackgroundCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.networkDidChange(isOnline: true)
        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.clock.date.addTimeInterval(3 * day)
        fixture.model.evaluate()

        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-6: 確認中(セッション中)は裏の確認を重ねない")
    func sessionInProgressBlocksBackgroundCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.isSessionInProgress = true
        fixture.model.networkDidChange(isOnline: true)
        fixture.model.evaluate()

        #expect(fixture.updater.backgroundCheckCount == 0)
    }

    @Test("AC-7: メニューの新しいバージョンの項目は、新しいバージョンがあるときだけ「新しいバージョンがあります(<バージョン>)」になる")
    func menuTitleAppearsOnlyWhenUpdateIsPending() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(fixture.model.menuTitleForPendingUpdate == nil)

        fixture.updater.send(.foundInBackground(version: "9.9.9"))
        #expect(fixture.model.menuTitleForPendingUpdate == "新しいバージョンがあります(9.9.9)")

        fixture.updater.send(.userAttended)
        #expect(fixture.model.menuTitleForPendingUpdate == nil)
    }

    @Test("AC-7: 新しいバージョンの項目を押しても、変更点の窓を出す前は項目が残り、押すたびに呼び出しが行われる")
    func showPendingUpdateKeepsItemUntilAttended() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.model.showPendingUpdate()
        fixture.model.showPendingUpdate()

        #expect(fixture.updater.userCheckCount == 2)
        #expect(fixture.model.menuTitleForPendingUpdate == "新しいバージョンがあります(1.3.0)")
    }

    @Test("AC-7: 新しいバージョンの項目を押すと、変更点の窓を出す呼び出しが1回行われる")
    func showPendingUpdateCallsUser() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.model.showPendingUpdate()

        #expect(fixture.updater.userCheckCount == 1)
    }

    @Test("AC-9: Dock のアイコンの印は、新しいバージョンがあるときだけ付く")
    func dockBadgeLabel() {
        #expect(UpdatePresentation.dockBadgeLabel(isUpdatePending: true) == "1")
        #expect(UpdatePresentation.dockBadgeLabel(isUpdatePending: false) == nil)
    }

    @Test("AC-11: 変更点の窓が出たら印が消える")
    func userAttendedClearsBadge() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.updater.send(.userAttended)

        #expect(fixture.model.pendingVersion == nil)
        #expect(fixture.model.menuTitleForPendingUpdate == nil)
        #expect(fixture.model.settingsStatusText == nil)
        #expect(fixture.model.badgedSettingsSections.isEmpty)
        #expect(UpdatePresentation.dockBadgeLabel(isUpdatePending: fixture.model.isUpdatePending) == nil)
    }

    @Test("AC-11: 窓を「後で通知」「このバージョンをスキップ」で閉じたら印が消え、その後の確認でまた見つかれば印が付く")
    func sessionFinishedClearsBadgeAndNextFindingBadgesAgain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.networkDidChange(isOnline: true)
        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.updater.send(.sessionFinished)
        #expect(fixture.model.pendingVersion == nil)
        #expect(fixture.model.badgedSettingsSections.isEmpty)

        fixture.updater.send(.checkCompleted)
        fixture.clock.date.addTimeInterval(day)
        fixture.model.evaluate()
        #expect(fixture.updater.backgroundCheckCount == 2)

        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        #expect(fixture.model.pendingVersion == "1.3.0")
        #expect(fixture.model.badgedSettingsSections == [.appInfo])
    }

    @Test("AC-11: 「後で通知」の直後の判定では、すぐ確かめ直さない")
    func laterDoesNotRecheckImmediately() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.model.networkDidChange(isOnline: true)
        fixture.updater.send(.checkCompleted)
        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.updater.send(.userAttended)
        fixture.updater.send(.sessionFinished)
        fixture.clock.date.addTimeInterval(60 * 60)
        fixture.model.evaluate()

        #expect(fixture.updater.backgroundCheckCount == 1)
    }

    @Test("AC-11: 印があるうちに自動の確認をオフにしても、印は残る")
    func disablingKeepsBadge() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        fixture.updater.send(.foundInBackground(version: "1.3.0"))
        fixture.model.isAutomaticCheckEnabled = false

        #expect(fixture.model.pendingVersion == "1.3.0")
        #expect(fixture.model.badgedSettingsSections == [.appInfo])
    }

    @Test("AC-11: 入れ替えで開き直す出来事を受けると、開き直しの通知を呼ぶ")
    func willRelaunchCallsHandler() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var relaunchCount = 0
        fixture.model.onWillRelaunch = { relaunchCount += 1 }
        fixture.updater.send(.willRelaunch)

        #expect(relaunchCount == 1)
    }

    @Test("AC-12: 手の確認が使えるかは、更新の仕組みの知らせを写す")
    func canCheckForUpdatesFollowsUpdater() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(fixture.model.canCheckForUpdates)
        fixture.updater.onCanCheckChange?(false)
        #expect(!fixture.model.canCheckForUpdates)
        fixture.updater.onCanCheckChange?(true)
        #expect(fixture.model.canCheckForUpdates)
    }

    @Test("AC-12: 何もしない更新の仕組みでは、手の確認は使えない")
    func inertModelCannotCheck() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(!UpdateModel.inert(settings: temporary.makeSettings()).canCheckForUpdates)
    }
}
