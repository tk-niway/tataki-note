import Foundation
import SwiftUI
import Testing
@testable import TatakiNote

@MainActor
struct DockAndQuitSettingsTests {
    private static let nonBooleanValues: [Any] = ["yes", "false", 1, 0, ["true"]]

    @Test("AC-1: Dock にアイコンを表示する設定は、何も保存されていなければオンで、作っただけでは保存しない")
    func showsDockIconDefaultsToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.showsDockIcon == true)
        #expect(defaults.object(forKey: SettingsStore.Key.showsDockIcon) == nil)
    }

    @Test("AC-1: Dock にアイコンを表示する設定を変えると保存され、同じ保存先で作り直しても残る")
    func showsDockIconSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.showsDockIcon = false
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == false)

        settings.showsDockIcon = true
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true)
    }

    @Test("AC-1: Dock にアイコンを表示する設定は、真偽値でない値が入っていればオン")
    func showsDockIconIgnoresNonBooleanValues() throws {
        for value in Self.nonBooleanValues {
            let name = UUID().uuidString
            let defaults = try #require(InMemoryDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }

            defaults.set(value, forKey: SettingsStore.Key.showsDockIcon)
            #expect(SettingsStore(defaults: defaults).loadShowsDockIcon() == true, "\(value)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true, "\(value)")
        }
    }

    @Test("AC-1: Dock にアイコンを表示する設定の保存は、ほかの設定を変えない")
    func showsDockIconIsIndependentOfOtherSettings() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.showsDockIcon = false

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.confirmsQuit == true)
        #expect(reloaded.hidesMenuBarIcon == settings.hidesMenuBarIcon)
    }

    @Test("AC-2: ⌘Q で終了前に確認する設定は、何も保存されていなければオンで、作っただけでは保存しない")
    func confirmsQuitDefaultsToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.confirmsQuit == true)
        #expect(defaults.object(forKey: SettingsStore.Key.confirmsQuit) == nil)
    }

    @Test("AC-2: ⌘Q で終了前に確認する設定を変えると保存され、同じ保存先で作り直しても残る")
    func confirmsQuitSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.confirmsQuit = false
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == false)

        settings.confirmsQuit = true
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == true)
    }

    @Test("AC-2: ⌘Q で終了前に確認する設定は、真偽値でない値が入っていればオン")
    func confirmsQuitIgnoresNonBooleanValues() throws {
        for value in Self.nonBooleanValues {
            let name = UUID().uuidString
            let defaults = try #require(InMemoryDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }

            defaults.set(value, forKey: SettingsStore.Key.confirmsQuit)
            #expect(SettingsStore(defaults: defaults).loadConfirmsQuit() == true, "\(value)")
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).confirmsQuit == true, "\(value)")
        }
    }

    @Test("AC-2: ⌘Q で終了前に確認する設定の保存は、Dock の設定を変えない")
    func confirmsQuitIsIndependentOfDockIcon() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.confirmsQuit = false

        #expect(AppSettings(store: SettingsStore(defaults: defaults)).showsDockIcon == true)
    }

    @Test("AC-28: 「メニューバーにアイコンを表示」は、何も保存されていなければオンで、作っただけでは保存しない")
    func isMenuBarIconShownDefaultsToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(settings.isMenuBarIconShown == true)
        #expect(defaults.object(forKey: SettingsStore.Key.hidesMenuBarIcon) == nil)
    }

    @Test("AC-28: 「メニューバーにアイコンを表示」をオフにすると hidesMenuBarIcon が true で保存され、作り直してもオフのまま")
    func isMenuBarIconShownSurvivesRecreation() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.isMenuBarIconShown = false
        #expect(defaults.bool(forKey: SettingsStore.Key.hidesMenuBarIcon) == true)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).isMenuBarIconShown == false)

        settings.isMenuBarIconShown = true
        #expect(defaults.bool(forKey: SettingsStore.Key.hidesMenuBarIcon) == false)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).isMenuBarIconShown == true)
    }

    @Test("AC-28: 「メニューバーにアイコンを表示」は、真偽値でない値が入っていればオン")
    func isMenuBarIconShownIgnoresNonBooleanValues() throws {
        for value in Self.nonBooleanValues {
            let name = UUID().uuidString
            let defaults = try #require(InMemoryDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }

            defaults.set(value, forKey: SettingsStore.Key.hidesMenuBarIcon)
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).isMenuBarIconShown == true, "\(value)")
        }
    }

    @Test("AC-28: アイコンを外したとき(MenuBarExtra の isInserted に結んだ値に false が書かれたとき)もオフになって保存される")
    func removingMenuBarIconTurnsSwitchOff() throws {
        let name = UUID().uuidString
        let defaults = try #require(InMemoryDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let isInserted = Binding(
            get: { settings.isMenuBarIconShown },
            set: { settings.isMenuBarIconShown = $0 }
        )
        #expect(isInserted.wrappedValue == true)

        isInserted.wrappedValue = false

        #expect(settings.isMenuBarIconShown == false)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).isMenuBarIconShown == false)
    }
}
