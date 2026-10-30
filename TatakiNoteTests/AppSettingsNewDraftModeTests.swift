import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppSettingsNewDraftModeTests {
    private func snapshot(_ defaults: InMemoryDefaults, keys: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, String(describing: defaults.object(forKey: $0))) })
    }

    @Test("AC-2: 保存値が無ければ、新しい書きかけのモードはインサート")
    func defaultsToInsert() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }

        #expect(defaults.makeSettings().newDraftMode == .insert)
        #expect(SettingsStore(defaults: defaults.defaults).loadNewDraftMode() == .insert)
    }

    @Test("AC-2: 新しい書きかけのモードは保存され、同じ保存先で作り直しても同じ値になる", arguments: DraftMode.allCases)
    func persistsAcrossRelaunch(mode: DraftMode) throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()

        settings.newDraftMode = mode

        #expect(defaults.defaults.string(forKey: SettingsStore.Key.newDraftMode) == mode.rawValue)
        #expect(defaults.makeSettings().newDraftMode == mode)
    }

    @Test("AC-2: 文字列でない・知らない値が保存されていたらインサート")
    func invalidStoredValueFallsBackToInsert() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let invalidValues: [Any] = [5, true, ["note"], "bogus", "", "Note"]

        for value in invalidValues {
            defaults.defaults.set(value, forKey: SettingsStore.Key.newDraftMode)
            #expect(defaults.makeSettings().newDraftMode == .insert)
        }
    }

    @Test("AC-2: 古いキー appMode に note が残っていても新しい書きかけのモードはインサートで、appMode は読み書きしない")
    func legacyAppModeIsIgnored() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        defaults.defaults.set("note", forKey: "appMode")

        let settings = defaults.makeSettings()
        #expect(settings.newDraftMode == .insert)

        settings.newDraftMode = .note
        #expect(defaults.defaults.string(forKey: "appMode") == "note")

        settings.newDraftMode = .insert
        #expect(defaults.defaults.string(forKey: "appMode") == "note")
        #expect(defaults.makeSettings().newDraftMode == .insert)
    }

    @Test("AC-2: 設定を作っただけでは新しい書きかけのモードも appMode も保存しない")
    func creatingSettingsSavesNothing() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }

        _ = defaults.makeSettings()

        #expect(defaults.defaults.object(forKey: SettingsStore.Key.newDraftMode) == nil)
        #expect(defaults.defaults.object(forKey: "appMode") == nil)
    }

    @Test("AC-8: 確定キーが両方とも未登録で、ホットキーが無ければ、初期値の2つを登録して保存する")
    func registersBothDefaultsWithoutHotkey() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.commitKey = nil
        settings.commitAndSendKey = nil

        settings.registerDefaultCommitKeysIfBothMissing(hotkey: nil)

        #expect(settings.commitKey == .commandShiftReturn)
        #expect(settings.commitAndSendKey == .commandReturn)
        let reloaded = defaults.makeSettings()
        #expect(reloaded.commitKey == .commandShiftReturn)
        #expect(reloaded.commitAndSendKey == .commandReturn)
    }

    @Test("AC-8: ホットキーが ⇧⌘↩ なら、確定+送信キーの ⌘↩ だけを登録する")
    func skipsCommitKeyEqualToHotkey() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.commitKey = nil
        settings.commitAndSendKey = nil

        settings.registerDefaultCommitKeysIfBothMissing(hotkey: .commandShiftReturn)

        #expect(settings.commitKey == nil)
        #expect(settings.commitAndSendKey == .commandReturn)
        let reloaded = defaults.makeSettings()
        #expect(reloaded.commitKey == nil)
        #expect(reloaded.commitAndSendKey == .commandReturn)
    }

    @Test("AC-8: ホットキーが ⌘↩ なら、確定+挿入キーの ⇧⌘↩ だけを登録する")
    func skipsCommitAndSendKeyEqualToHotkey() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let settings = defaults.makeSettings()
        settings.commitKey = nil
        settings.commitAndSendKey = nil

        settings.registerDefaultCommitKeysIfBothMissing(hotkey: .commandReturn)

        #expect(settings.commitKey == .commandShiftReturn)
        #expect(settings.commitAndSendKey == nil)
        let reloaded = defaults.makeSettings()
        #expect(reloaded.commitKey == .commandShiftReturn)
        #expect(reloaded.commitAndSendKey == nil)
    }

    @Test("AC-8: どちらかが登録済みなら何も変えず、保存もしない")
    func leavesKeysAloneWhenEitherIsRegistered() throws {
        let defaults = try TemporaryDefaults()
        defer { defaults.remove() }
        let keys = [SettingsStore.Key.commitShortcut, SettingsStore.Key.commitAndSendShortcut]

        let onlyCommit = defaults.makeSettings()
        onlyCommit.commitKey = .commandReturn
        onlyCommit.commitAndSendKey = nil
        var before = snapshot(defaults.defaults, keys: keys)
        onlyCommit.registerDefaultCommitKeysIfBothMissing(hotkey: nil)
        #expect(onlyCommit.commitKey == .commandReturn)
        #expect(onlyCommit.commitAndSendKey == nil)
        #expect(snapshot(defaults.defaults, keys: keys) == before)

        let onlySend = defaults.makeSettings()
        onlySend.commitKey = nil
        onlySend.commitAndSendKey = .commandShiftReturn
        before = snapshot(defaults.defaults, keys: keys)
        onlySend.registerDefaultCommitKeysIfBothMissing(hotkey: nil)
        #expect(onlySend.commitKey == nil)
        #expect(onlySend.commitAndSendKey == .commandShiftReturn)
        #expect(snapshot(defaults.defaults, keys: keys) == before)
    }
}
