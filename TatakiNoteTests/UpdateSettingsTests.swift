import Foundation
import Testing
@testable import TatakiNote

@MainActor
private final class SettingsFakeUpdater: UpdaterDriving {
    var onEvent: ((UpdaterEvent) -> Void)?
    var onCanCheckChange: ((Bool) -> Void)?
    var canCheckForUpdates = true
    var isSessionInProgress = false
    private(set) var userCheckCount = 0

    func start() {}

    func checkInBackground() {}

    func checkByUser() {
        userCheckCount += 1
    }

    func send(_ event: UpdaterEvent) {
        onEvent?(event)
    }
}

@MainActor
struct UpdateSettingsTests {
    @Test("AC-10: 新しい版が無いとき、設定の印も状態の文言も無い")
    func noBadgeWithoutPendingUpdate() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let model = UpdateModel(settings: temporary.makeSettings(), updater: SettingsFakeUpdater())

        #expect(model.badgedSettingsSections.isEmpty)
        #expect(model.settingsStatusText == nil)
    }

    @Test("AC-10: 新しい版があるとき、「情報」に印が付き、状態の文言に版が入る")
    func badgeAndStatusTextForPendingUpdate() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)
        updater.send(.foundInBackground(version: "9.9.9"))

        #expect(model.badgedSettingsSections == [.appInfo])
        #expect(model.settingsStatusText == "新しい版 9.9.9 があります")
    }

    @Test("AC-10: 「詳しく見る…」で変更点の窓を出す処理を呼び、窓を見たら印と文言が消える")
    func showingPendingUpdateClearsBadge() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)
        updater.send(.foundInBackground(version: "1.3.0"))

        model.showPendingUpdate()
        #expect(updater.userCheckCount == 1)

        updater.send(.userAttended)
        #expect(model.badgedSettingsSections.isEmpty)
        #expect(model.settingsStatusText == nil)
    }

    @Test("AC-10: 自動の確認をオフにしても、見つけた版の印は残る")
    func badgeStaysWhenAutomaticCheckIsOff() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)
        updater.send(.foundInBackground(version: "1.3.0"))
        model.isAutomaticCheckEnabled = false

        #expect(model.badgedSettingsSections == [.appInfo])
        #expect(model.settingsStatusText == "新しい版 1.3.0 があります")
    }

    @Test("AC-10: 自動の確認の説明文は、1日に1回新しい版を確かめることだけを伝える")
    func automaticCheckHelpTextOnlyDescribesDailyCheck() {
        #expect(SettingsHelpText.automaticUpdateCheck == "1日に1回、新しい版があるかを確かめます。")
    }

    @Test("AC-12: 更新の仕組みの「確認できるか」が、画面に出す値に写る")
    func canCheckForUpdatesFollowsUpdater() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)
        #expect(model.canCheckForUpdates)

        updater.onCanCheckChange?(false)
        #expect(!model.canCheckForUpdates)

        updater.onCanCheckChange?(true)
        #expect(model.canCheckForUpdates)
    }

    @Test("AC-12: 確認できない更新の仕組みで始めると、最初から確認できない")
    func canCheckForUpdatesStartsFromUpdater() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        updater.canCheckForUpdates = false
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)

        #expect(!model.canCheckForUpdates)
    }

    @Test("AC-12: 何もしない更新の仕組みでは、確認できない")
    func inertModelCannotCheck() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(!UpdateModel.inert(settings: temporary.makeSettings()).canCheckForUpdates)
    }

    @Test("AC-12: 自動の確認がオフでも、「アップデートを確認…」は手の確認を始める")
    func manualCheckWorksWhenAutomaticCheckIsOff() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let updater = SettingsFakeUpdater()
        let model = UpdateModel(settings: temporary.makeSettings(), updater: updater)
        model.isAutomaticCheckEnabled = false

        model.checkByUser()

        #expect(updater.userCheckCount == 1)
    }

    @Test("AC-1: 自動の確認の初期値はオン")
    func automaticCheckDefaultsToOn() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(temporary.makeSettings().checksForUpdatesAutomatically)
        #expect(UpdateModel.inert(settings: temporary.makeSettings()).isAutomaticCheckEnabled)
    }

    @Test("AC-1: 自動の確認を切り替えた値は、作り直した設定でも残る")
    func automaticCheckSurvivesRecreation() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let settings = temporary.makeSettings()
        settings.checksForUpdatesAutomatically = false
        #expect(!temporary.makeSettings().checksForUpdatesAutomatically)

        settings.checksForUpdatesAutomatically = true
        #expect(temporary.makeSettings().checksForUpdatesAutomatically)
    }

    @Test("AC-1: 自動の確認の保存が真偽値でない(文字列・数値)ならオン")
    func automaticCheckReadsBrokenValueAsOn() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        temporary.defaults.set("false", forKey: SettingsStore.Key.checksForUpdatesAutomatically)
        #expect(temporary.makeSettings().checksForUpdatesAutomatically)

        temporary.defaults.set(0, forKey: SettingsStore.Key.checksForUpdatesAutomatically)
        #expect(temporary.makeSettings().checksForUpdatesAutomatically)
    }

    @Test("AC-1: 設定画面のスイッチの値は設定に書き込まれる")
    func modelWritesAutomaticCheckToSettings() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let settings = temporary.makeSettings()
        let model = UpdateModel.inert(settings: settings)
        model.isAutomaticCheckEnabled = false

        #expect(!settings.checksForUpdatesAutomatically)
        #expect(!temporary.makeSettings().checksForUpdatesAutomatically)
    }

    @Test("AC-5: 前回の確認の日時の初期値は未確認")
    func lastCheckDateDefaultsToNil() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(temporary.makeSettings().lastUpdateCheckDate == nil)
    }

    @Test("AC-5: 前回の確認の日時は、作り直した設定でも残り、nil に戻せる")
    func lastCheckDateSurvivesRecreation() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = temporary.makeSettings()
        settings.lastUpdateCheckDate = date
        #expect(temporary.makeSettings().lastUpdateCheckDate == date)

        settings.lastUpdateCheckDate = nil
        #expect(temporary.makeSettings().lastUpdateCheckDate == nil)
    }

    @Test("AC-5: 前回の確認の日時が数値でない(文字列)・有限でない(NaN・無限大)なら未確認として読む")
    func lastCheckDateReadsBrokenValueAsNil() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let key = SettingsStore.Key.lastUpdateCheckDate
        for broken: Any in ["2026-10-21", Double.nan, Double.infinity, -Double.infinity, true] {
            temporary.defaults.set(broken, forKey: key)
            #expect(temporary.makeSettings().lastUpdateCheckDate == nil)
        }
    }

    @Test("AC-20: 「今後は聞かない」の初期値は聞く")
    func suppressionDefaultsToAsking() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        #expect(!temporary.makeSettings().suppressesMoveToApplicationsPrompt)
    }

    @Test("AC-20: 「今後は聞かない」は、作り直した設定でも残る")
    func suppressionSurvivesRecreation() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        temporary.makeSettings().suppressesMoveToApplicationsPrompt = true
        #expect(temporary.makeSettings().suppressesMoveToApplicationsPrompt)
    }

    @Test("AC-20: 「今後は聞かない」の保存が真偽値でない(文字列・数値)なら聞く")
    func suppressionReadsBrokenValueAsAsking() throws {
        let temporary = try TemporaryDefaults()
        defer { temporary.remove() }

        let key = SettingsStore.Key.suppressesMoveToApplicationsPrompt
        temporary.defaults.set("true", forKey: key)
        #expect(!temporary.makeSettings().suppressesMoveToApplicationsPrompt)

        temporary.defaults.set(1, forKey: key)
        #expect(!temporary.makeSettings().suppressesMoveToApplicationsPrompt)
    }
}
