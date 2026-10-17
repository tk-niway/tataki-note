import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AnimationModeSettingTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test("AC-1: 保存が無いときは「アニメーション」がオンで動きを使い、作っただけでは何も保存しない")
    func defaultsToOnWithoutSavedValue() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            #expect(store.loadAnimationMode() == .on)

            let settings = AppSettings(store: store, reducesMotion: { false })
            #expect(settings.animationMode == .on)
            #expect(settings.isAnimationEnabled)
            #expect(defaults.object(forKey: SettingsStore.Key.animationMode) == nil)
        }
    }

    @Test("AC-2: 古いキー panelAnimationEnabled に false・true が保存されていても、オンから始まる")
    func legacyKeyIsIgnored() throws {
        try withDefaults { defaults in
            for value in [false, true] {
                defaults.set(value, forKey: "panelAnimationEnabled")

                let settings = AppSettings(store: SettingsStore(defaults: defaults), reducesMotion: { false })

                #expect(settings.animationMode == .on, "\(value)")
                #expect(settings.isAnimationEnabled, "\(value)")
                #expect(defaults.object(forKey: SettingsStore.Key.animationMode) == nil, "\(value)")
            }
        }
    }

    @Test("AC-3: 選んだ値が system・on・off の文字列で保存され、同じ保存先から作り直しても残る", arguments: AnimationMode.allCases)
    func selectedModeIsSavedAndSurvivesRecreation(mode: AnimationMode) throws {
        try withDefaults { defaults in
            let settings = AppSettings(store: SettingsStore(defaults: defaults))
            settings.animationMode = mode

            #expect(defaults.string(forKey: SettingsStore.Key.animationMode) == mode.rawValue)
            #expect(AppSettings(store: SettingsStore(defaults: defaults)).animationMode == mode)
        }
    }

    @Test("AC-3: 保存の文字列は system・on・off")
    func rawValuesAreStable() {
        #expect(AnimationMode.system.rawValue == "system")
        #expect(AnimationMode.on.rawValue == "on")
        #expect(AnimationMode.off.rawValue == "off")
        #expect(AnimationMode.allCases == [.system, .on, .off])
    }

    @Test("AC-3: 知らない文字列・文字列でない値が保存されていればオンになる")
    func unknownStoredValuesFallBackToOn() throws {
        try withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let badValues: [Any] = ["", "ON", "enabled", "true", 0, 1, 2.5, true, ["off"]]
            for value in badValues {
                defaults.set(value, forKey: SettingsStore.Key.animationMode)

                #expect(store.loadAnimationMode() == .on, "\(value)")
                #expect(AppSettings(store: store).animationMode == .on, "\(value)")
            }
        }
    }

    @Test("AC-4: 動きを使うかは、オンなら使い、オフなら使わず、システムは視差効果を減らしていなければ使う")
    func isEnabledFollowsModeAndReduceMotion() {
        #expect(AnimationMode.system.isEnabled(reduceMotion: false))
        #expect(!AnimationMode.system.isEnabled(reduceMotion: true))
        #expect(AnimationMode.on.isEnabled(reduceMotion: false))
        #expect(AnimationMode.on.isEnabled(reduceMotion: true))
        #expect(!AnimationMode.off.isEnabled(reduceMotion: false))
        #expect(!AnimationMode.off.isEnabled(reduceMotion: true))
    }

    @Test("AC-4: システムのまま視差効果を減らす設定が変わると、次に読んだときから従う")
    func systemFollowsReduceMotionChanges() throws {
        try withDefaults { defaults in
            var reducesMotion = false
            let settings = AppSettings(store: SettingsStore(defaults: defaults), reducesMotion: { reducesMotion })
            settings.animationMode = .system
            #expect(settings.isAnimationEnabled)

            reducesMotion = true
            #expect(!settings.isAnimationEnabled)

            reducesMotion = false
            #expect(settings.isAnimationEnabled)
        }
    }

    @Test("AC-4: オン・オフは視差効果を減らす設定に関わらず選んだとおり")
    func onAndOffIgnoreReduceMotion() throws {
        try withDefaults { defaults in
            for reducesMotion in [false, true] {
                let settings = AppSettings(store: SettingsStore(defaults: defaults), reducesMotion: { reducesMotion })
                settings.animationMode = .on
                #expect(settings.isAnimationEnabled, "\(reducesMotion)")
                settings.animationMode = .off
                #expect(!settings.isAnimationEnabled, "\(reducesMotion)")
            }
        }
    }
}
