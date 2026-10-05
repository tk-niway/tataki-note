import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionFailureBubbleModelTests {
    private func makeSettings(name: String) throws -> (AppSettings, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: name))
        return (AppSettings(store: SettingsStore(defaults: defaults)), defaults)
    }

    // MARK: - 状態

    @Test("吹き出しの状態: present で出ている状態になり番号が1ずつ増え、dismiss で出ていない状態に戻る")
    func presentAndDismiss() {
        let model = InsertionFailureBubbleModel()
        #expect(model.isPresented == false)
        #expect(model.presentationID == 0)

        let first = model.present()
        #expect(first == 1)
        #expect(model.isPresented == true)

        let second = model.present()
        #expect(second == 2)
        #expect(model.presentationID == 2)
        #expect(model.isPresented == true)

        model.dismiss()
        #expect(model.isPresented == false)
        #expect(model.presentationID == 2)
        model.dismiss()
        #expect(model.isPresented == false)
    }

    @Test("吹き出しを出している間は、アイコンを一時的に出す必要がある")
    func forcesMenuBarIconWhilePresented() {
        let model = InsertionFailureBubbleModel()
        #expect(model.forcesMenuBarIcon == false)
        model.present()
        #expect(model.forcesMenuBarIcon == true)
        model.dismiss()
        #expect(model.forcesMenuBarIcon == false)
    }

    @Test("吹き出しは5秒で閉じる設計の長さを持つ")
    func displayDuration() {
        #expect(InsertionFailureBubbleModel.displayDuration == .seconds(5))
    }

    // MARK: - AC-2

    @Test("AC-2: 吹き出しの文は「挿入できませんでした」だけで、理由・アプリ名・下書きの状態の文を含まない")
    func messageIsOnlyFailureSentence() {
        let message = InsertionFailureBubbleModel.message
        #expect(message == "挿入できませんでした")
        #expect(message.contains("下書き") == false)
        #expect(message.contains("アプリ") == false)
        #expect(message.contains("入力欄") == false)
        #expect(message.contains("\n") == false)
    }

    // MARK: - AC-7

    @Test("AC-7: アイコンを出す設定のときは、吹き出しの有無にかかわらずアイコンが出る")
    func iconStaysInsertedWhenSettingShowsIt() {
        let model = InsertionFailureBubbleModel()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: true) == true)
        model.present()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: true) == true)
        model.dismiss()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: true) == true)
    }

    @Test("AC-7: アイコンを隠す設定のときは、吹き出しを出している間だけアイコンが出る")
    func iconInsertedOnlyWhilePresentedWhenHidden() {
        let model = InsertionFailureBubbleModel()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: false) == false)
        model.present()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: false) == true)
        model.dismiss()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: false) == false)
    }

    @Test("AC-7: アイコンを隠す設定は、吹き出しを出して閉じても保存値がオンのまま変わらない")
    func hiddenSettingSurvivesBubble() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        settings.hidesMenuBarIcon = true
        let model = InsertionFailureBubbleModel()

        model.present()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: settings.isMenuBarIconShown) == true)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)

        model.dismiss()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: settings.isMenuBarIconShown) == false)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hidesMenuBarIcon == true)
    }

    @Test("AC-7: アイコンを出す設定のままなら、吹き出しを出して閉じても保存値は出すのまま")
    func shownSettingSurvivesBubble() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let model = InsertionFailureBubbleModel()

        model.present()
        model.dismiss()
        #expect(model.isMenuBarIconInserted(isIconShownSetting: settings.isMenuBarIconShown) == true)
        #expect(settings.hidesMenuBarIcon == false)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == false)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hidesMenuBarIcon == false)
    }

    // MARK: - menuBarIconInsertionDidChange(AC-8 のモデルの側)

    @Test("吹き出しのために一時的にアイコンを出している間に出すが書き戻されても、アイコンを隠す設定はオフにならない")
    func writeBackWhileForcedKeepsHiddenSetting() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        settings.hidesMenuBarIcon = true
        let model = InsertionFailureBubbleModel()
        model.present()

        let shouldClose = model.menuBarIconInsertionDidChange(to: true, settings: settings)

        #expect(shouldClose == false)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hidesMenuBarIcon == true)
    }

    @Test("吹き出しを出していないときに出すが書き戻されたら、今までどおりアイコンを出す設定になる")
    func writeBackWhileNotForcedShowsIcon() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        settings.hidesMenuBarIcon = true
        let model = InsertionFailureBubbleModel()

        let shouldClose = model.menuBarIconInsertionDidChange(to: true, settings: settings)

        #expect(shouldClose == false)
        #expect(settings.hidesMenuBarIcon == false)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == false)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hidesMenuBarIcon == false)
    }

    @Test("吹き出しを出している間に利用者がアイコンを外したら、アイコンを隠す設定がオンになり、吹き出しを閉じるべきと返す")
    func removalWhilePresentedHidesIconAndClosesBubble() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let model = InsertionFailureBubbleModel()
        model.present()

        let shouldClose = model.menuBarIconInsertionDidChange(to: false, settings: settings)

        #expect(shouldClose == true)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
        #expect(AppSettings(store: SettingsStore(defaults: defaults)).hidesMenuBarIcon == true)
    }

    @Test("吹き出しを出していないときに利用者がアイコンを外したら、アイコンを隠す設定がオンになり、閉じるものは無い")
    func removalWhileNotPresentedHidesIcon() throws {
        let name = UUID().uuidString
        let (settings, defaults) = try makeSettings(name: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let model = InsertionFailureBubbleModel()

        let shouldClose = model.menuBarIconInsertionDidChange(to: false, settings: settings)

        #expect(shouldClose == false)
        #expect(settings.hidesMenuBarIcon == true)
        #expect(defaults.bool(forKey: "hidesMenuBarIcon") == true)
    }
}
