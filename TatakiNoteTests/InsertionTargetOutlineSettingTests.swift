import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionTargetOutlineSettingTests {
    @Test("AC-1: 保存が無いときは枠線がオンで始まり、作っただけでは何も保存しない")
    func defaultsToOnWithoutSavedValue() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.loadIsInsertionTargetOutlineShown() == true)

        let settings = AppSettings(store: store)
        #expect(settings.isInsertionTargetOutlineShown == true)
        #expect(defaults.object(forKey: SettingsStore.Key.insertionTargetOutlineShown) == nil)
    }

    @Test("AC-1: 真偽値でない値(文字列・数値・配列)が保存されていてもオンになる")
    func nonBooleanValuesFallBackToOn() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        let badValues: [Any] = ["yes", "false", "", 0, 1, 2.5, ["false"]]
        for value in badValues {
            defaults.set(value, forKey: SettingsStore.Key.insertionTargetOutlineShown)
            #expect(store.loadIsInsertionTargetOutlineShown() == true, "\(value)")
            #expect(AppSettings(store: store).isInsertionTargetOutlineShown == true, "\(value)")
        }
    }

    @Test("AC-1: 保存のキーは insertionTargetOutlineShown")
    func storageKeyName() {
        #expect(SettingsStore.Key.insertionTargetOutlineShown == "insertionTargetOutlineShown")
    }

    @Test("AC-1: オフにすると保存され、同じ保存先から作り直した設定でもオフのまま。オンに戻すとオンで保存される")
    func offSurvivesRecreationAndOnIsSaved() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        settings.isInsertionTargetOutlineShown = false
        #expect(defaults.object(forKey: "insertionTargetOutlineShown") as? Bool == false)

        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.isInsertionTargetOutlineShown == false)

        reloaded.isInsertionTargetOutlineShown = true
        #expect(defaults.object(forKey: "insertionTargetOutlineShown") as? Bool == true)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).isInsertionTargetOutlineShown == true)
    }

    @Test("AC-1: 保存先に書いた真偽値のオフを、作り直した設定が読む")
    func storedFalseIsLoadedAsOff() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        store.saveIsInsertionTargetOutlineShown(false)
        #expect(store.loadIsInsertionTargetOutlineShown() == false)
        #expect(AppSettings(store: store).isInsertionTargetOutlineShown == false)
    }
}
