import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct DockAndQuitSettingsTests {
    private static let nonBooleanValues: [Any] = ["yes", "false", 1, 0, ["true"]]

    @Test("AC-1: Dock にアイコンを出す設定は、何も保存されていなければオンで、作っただけでは保存しない")
    func showsDockIconDefaultsToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.showsDockIcon == true)
        #expect(defaults.object(forKey: SettingsStore.Key.showsDockIcon) == nil)
    }

    @Test("AC-1: Dock にアイコンを出す設定を変えると保存され、同じ保存先で作り直しても残る")
    func showsDockIconSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.showsDockIcon = false
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == false)

        settings.showsDockIcon = true
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true)
    }

    @Test("AC-1: Dock にアイコンを出す設定は、真偽値でない値が入っていればオン")
    func showsDockIconIgnoresNonBooleanValues() throws {
        for value in Self.nonBooleanValues {
            let name = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }

            defaults.set(value, forKey: SettingsStore.Key.showsDockIcon)
            #expect(SettingsStore(defaults: defaults).loadShowsDockIcon() == true, "\(value)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true, "\(value)")
        }
    }

    @Test("AC-1: Dock にアイコンを出す設定の保存は、ほかの設定を変えない")
    func showsDockIconIsIndependentOfOtherSettings() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.showsDockIcon = false

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.confirmsQuit == true)
        #expect(reloaded.hidesMenuBarIcon == settings.hidesMenuBarIcon)
    }

    @Test("AC-2: ⌘Q で終了する前に確かめる設定は、何も保存されていなければオンで、作っただけでは保存しない")
    func confirmsQuitDefaultsToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.confirmsQuit == true)
        #expect(defaults.object(forKey: SettingsStore.Key.confirmsQuit) == nil)
    }

    @Test("AC-2: ⌘Q で終了する前に確かめる設定を変えると保存され、同じ保存先で作り直しても残る")
    func confirmsQuitSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.confirmsQuit = false
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == false)

        settings.confirmsQuit = true
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == true)
    }

    @Test("AC-2: ⌘Q で終了する前に確かめる設定は、真偽値でない値が入っていればオン")
    func confirmsQuitIgnoresNonBooleanValues() throws {
        for value in Self.nonBooleanValues {
            let name = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }

            defaults.set(value, forKey: SettingsStore.Key.confirmsQuit)
            #expect(SettingsStore(defaults: defaults).loadConfirmsQuit() == true, "\(value)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == true, "\(value)")
        }
    }

    @Test("AC-2: ⌘Q で終了する前に確かめる設定の保存は、Dock の設定を変えない")
    func confirmsQuitIsIndependentOfDockIcon() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.confirmsQuit = false

        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true)
    }
}
