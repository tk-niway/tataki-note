import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct UpdateSettingsTests {
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
