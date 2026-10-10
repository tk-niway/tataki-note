import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct AppModeSettingsTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, name)
    }

    private func settings(_ defaults: UserDefaults) -> AppSettings {
        AppSettings(store: SettingsStore(defaults: defaults))
    }

    // MARK: - AC-1

    @Test("AC-1: 保存値が無く、確定キーが初期値のままならインサートモード。作っただけでは何も保存しない")
    func defaultsToInsertModeWithoutSaving() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        #expect(loaded.appMode == .insert)
        #expect(!loaded.isNoteMode)
        #expect(defaults.object(forKey: "appMode") == nil)
        #expect(defaults.object(forKey: "commitShortcut") == nil)
        #expect(defaults.object(forKey: "commitAndSendShortcut") == nil)
    }

    @Test("AC-1: 保存値が無く、確定キーのどちらかが登録されていればインサートモード")
    func insertModeWhenEitherKeyIsRegistered() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set([], forKey: "commitShortcut")
        #expect(settings(defaults).appMode == .insert)

        defaults.set(PanelShortcut.commandReturn.storedValue, forKey: "commitAndSendShortcut")
        defaults.set([], forKey: "commitShortcut")
        #expect(settings(defaults).appMode == .insert)

        defaults.set(PanelShortcut.shiftReturn.storedValue, forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        #expect(settings(defaults).appMode == .insert)
    }

    @Test("AC-1: 保存値が無く、確定キーが両方とも未登録で保存されていればノートモード。作っただけでは保存しない")
    func noteModeWhenBothKeysAreUnregistered() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")

        let loaded = settings(defaults)
        #expect(loaded.appMode == .note)
        #expect(loaded.isNoteMode)
        #expect(defaults.object(forKey: "appMode") == nil)
    }

    @Test("AC-1: 読めない保存値は、保存値が無いときと同じ決め方になる")
    func unreadableStoredModeFallsBackToKeyBasedChoice() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("unknown", forKey: "appMode")
        #expect(settings(defaults).appMode == .insert)

        defaults.set(42, forKey: "appMode")
        #expect(settings(defaults).appMode == .insert)

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        defaults.set("unknown", forKey: "appMode")
        #expect(settings(defaults).appMode == .note)
    }

    @Test("AC-1: モードの保存値があれば、確定キーの保存値より優先する")
    func storedModeWinsOverKeys() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        defaults.set("insert", forKey: "appMode")
        #expect(settings(defaults).appMode == .insert)

        defaults.set(PanelShortcut.commandReturn.storedValue, forKey: "commitShortcut")
        defaults.set("note", forKey: "appMode")
        #expect(settings(defaults).appMode == .note)
    }

    // MARK: - AC-2

    @Test("AC-2: モードを切り替えると保存され、同じ保存先で作り直しても同じモードになる")
    func selectedModeSurvivesRecreation() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let first = settings(defaults)
        first.selectAppMode(.note, hotkey: nil)
        #expect(first.appMode == .note)
        #expect(defaults.string(forKey: "appMode") == "note")
        #expect(settings(defaults).appMode == .note)

        first.selectAppMode(.insert, hotkey: nil)
        #expect(first.appMode == .insert)
        #expect(defaults.string(forKey: "appMode") == "insert")
        #expect(settings(defaults).appMode == .insert)
    }

    @Test("AC-2: 同じモードを選んでも何も変わらず、何も保存しない")
    func selectingSameModeDoesNothing() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        loaded.selectAppMode(.insert, hotkey: nil)
        #expect(loaded.appMode == .insert)
        #expect(defaults.object(forKey: "appMode") == nil)

        loaded.selectAppMode(.note, hotkey: nil)
        defaults.removeObject(forKey: "appMode")
        loaded.selectAppMode(.note, hotkey: nil)
        #expect(loaded.appMode == .note)
        #expect(defaults.object(forKey: "appMode") == nil)
    }

    // MARK: - AC-3

    @Test("AC-3: ノートモードにしても確定キーの値と保存値は変わらず、インサートモードに戻すと元のキーのまま")
    func noteModeKeepsCommitKeys() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let both = settings(defaults)
        both.commitKey = .shiftReturn
        both.commitAndSendKey = .commandShiftReturn
        both.selectAppMode(.note, hotkey: nil)
        #expect(both.commitKey == .shiftReturn)
        #expect(both.commitAndSendKey == .commandShiftReturn)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == PanelShortcut.shiftReturn.storedValue)
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)
        both.selectAppMode(.insert, hotkey: nil)
        #expect(both.commitKey == .shiftReturn)
        #expect(both.commitAndSendKey == .commandShiftReturn)
        let reloadedBoth = settings(defaults)
        #expect(reloadedBoth.commitKey == .shiftReturn)
        #expect(reloadedBoth.commitAndSendKey == .commandShiftReturn)
    }

    @Test("AC-3: 片方だけ登録していても、ノートモードを挟んで元のまま")
    func noteModeKeepsSingleCommitKey() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let single = settings(defaults)
        single.commitKey = nil
        single.commitAndSendKey = .commandReturn
        single.selectAppMode(.note, hotkey: nil)
        #expect(single.commitKey == nil)
        #expect(single.commitAndSendKey == .commandReturn)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == [])
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandReturn.storedValue)
        single.selectAppMode(.insert, hotkey: nil)
        #expect(single.commitKey == nil)
        #expect(single.commitAndSendKey == .commandReturn)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == [])
    }

    // MARK: - AC-4

    @Test("AC-4: 両方とも未登録のままインサートモードにすると、初期値の ⇧⌘↩・⌘↩ が登録・保存される")
    func insertModeRegistersDefaultKeysWhenBothUnregistered() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        let loaded = settings(defaults)
        #expect(loaded.appMode == .note)

        loaded.selectAppMode(.insert, hotkey: nil)
        #expect(loaded.appMode == .insert)
        #expect(loaded.commitKey == .commandShiftReturn)
        #expect(loaded.commitAndSendKey == .commandReturn)
        #expect(defaults.array(forKey: "commitShortcut") as? [Int] == PanelShortcut.commandShiftReturn.storedValue)
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == PanelShortcut.commandReturn.storedValue)
        let reloaded = settings(defaults)
        #expect(reloaded.commitKey == .commandShiftReturn)
        #expect(reloaded.commitAndSendKey == .commandReturn)
    }

    @Test("AC-4: ホットキーが初期値の片方と同じなら、その片方は登録しない")
    func insertModeSkipsDefaultKeyUsedByHotkey() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        let sameAsCommit = settings(defaults)
        sameAsCommit.selectAppMode(.insert, hotkey: .commandShiftReturn)
        #expect(sameAsCommit.commitKey == nil)
        #expect(sameAsCommit.commitAndSendKey == .commandReturn)

        defaults.set([], forKey: "commitShortcut")
        defaults.set([], forKey: "commitAndSendShortcut")
        defaults.removeObject(forKey: "appMode")
        let sameAsSend = settings(defaults)
        sameAsSend.selectAppMode(.insert, hotkey: .commandReturn)
        #expect(sameAsSend.commitKey == .commandShiftReturn)
        #expect(sameAsSend.commitAndSendKey == nil)
    }

    @Test("AC-4: どちらかが登録済みなら、インサートモードにしても確定キーは変わらない")
    func insertModeKeepsRegisteredKeys() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let only = settings(defaults)
        only.commitKey = .shiftReturn
        only.commitAndSendKey = nil
        only.selectAppMode(.note, hotkey: nil)
        only.selectAppMode(.insert, hotkey: nil)
        #expect(only.commitKey == .shiftReturn)
        #expect(only.commitAndSendKey == nil)
        #expect(defaults.array(forKey: "commitAndSendShortcut") as? [Int] == [])

        let other = settings(defaults)
        other.selectAppMode(.note, hotkey: nil)
        other.commitKey = nil
        other.commitAndSendKey = .shiftReturn
        other.selectAppMode(.insert, hotkey: nil)
        #expect(other.commitKey == nil)
        #expect(other.commitAndSendKey == .shiftReturn)
    }

    @Test("AC-4: ノートモードにするときは、確定キーが両方とも未登録でも初期値を登録しない")
    func noteModeDoesNotRegisterDefaultKeys() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        loaded.commitKey = nil
        loaded.commitAndSendKey = nil
        loaded.selectAppMode(.note, hotkey: nil)
        #expect(loaded.commitKey == nil)
        #expect(loaded.commitAndSendKey == nil)
    }

    // MARK: - AC-5

    @Test("AC-5: 効く「パネルを出す位置」は、ノートモードでだけ「入力欄の近く」がマウスのある画面になる。保存値は変わらない")
    func effectivePanelScreenFollowsMode() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        for screen in PanelScreen.allCases {
            loaded.panelScreen = screen
            loaded.selectAppMode(.insert, hotkey: nil)
            #expect(loaded.effectivePanelScreen == screen)

            loaded.selectAppMode(.note, hotkey: nil)
            let expected: PanelScreen = screen == .nearFocusedField ? .mouse : screen
            #expect(loaded.effectivePanelScreen == expected)
            #expect(loaded.panelScreen == screen)
            #expect(defaults.string(forKey: "panelScreen") == screen.rawValue)
        }
    }

    @Test("AC-5: 効く自動表示は、ノートモードでオフになる。自動表示と対象のアプリの保存値は変わらない")
    func effectiveAutoShowModeFollowsMode() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        loaded.autoShowApps = [AutoShowApp(bundleIdentifier: "com.example.notes", name: "Notes")]
        let apps = loaded.autoShowApps
        for mode in AutoShowMode.allCases {
            loaded.autoShowMode = mode
            loaded.selectAppMode(.insert, hotkey: nil)
            #expect(loaded.effectiveAutoShowMode == mode)

            loaded.selectAppMode(.note, hotkey: nil)
            #expect(loaded.effectiveAutoShowMode == .off)
            #expect(loaded.autoShowMode == mode)
            #expect(defaults.string(forKey: "autoShowMode") == mode.rawValue)
            #expect(loaded.autoShowApps == apps)
        }
    }

    @Test("AC-5: 挿入先の枠線は、ノートモードで効かなくなる。保存値は変わらず、インサートモードに戻すとそのまま効く")
    func insertionTargetOutlineIsInactiveInNoteMode() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        for isShown in [true, false] {
            loaded.isInsertionTargetOutlineShown = isShown
            loaded.selectAppMode(.insert, hotkey: nil)
            #expect(loaded.isInsertionTargetOutlineActive == isShown)

            loaded.selectAppMode(.note, hotkey: nil)
            #expect(!loaded.isInsertionTargetOutlineActive)
            #expect(loaded.isInsertionTargetOutlineShown == isShown)
            #expect(defaults.object(forKey: "insertionTargetOutlineShown") as? Bool == isShown)
        }
    }

    @Test("AC-5, AC-7: 帯の項目は、ノートモードで改行と確定キー2つが除かれ、閉じると文字数・行数は残り、インサートモードでは今と同じ")
    func panelStatusItemsDropLineBreakAndCommitKeysInNoteMode() throws {
        let (defaults, name) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let loaded = settings(defaults)
        #expect(loaded.panelStatusItems == [.close, .lineBreak, .commit, .commitAndSend, .characterCount, .lineCount])

        loaded.selectAppMode(.note, hotkey: nil)
        #expect(loaded.panelStatusItems == [.close, .characterCount, .lineCount])
        #expect(loaded.commitKey == .commandShiftReturn)
        #expect(!loaded.hiddenPanelStatusItems.contains(.lineBreak))

        loaded.selectAppMode(.insert, hotkey: nil)
        #expect(loaded.panelStatusItems == [.close, .lineBreak, .commit, .commitAndSend, .characterCount, .lineCount])
    }

    // MARK: - AC-25

    @Test("AC-25: 「ショートカットキー」の説明文は、インサートモードでは今の文、ノートモードでは確定キーの項目を指さない文")
    func shortcutSettingDescriptionFollowsMode() {
        #expect(EditorShortcuts.settingDescription(isNoteMode: false) == EditorShortcuts.settingDescription)

        let note = EditorShortcuts.settingDescription(isNoteMode: true)
        #expect(note == EditorShortcuts.noteModeSettingDescription)
        #expect(note != EditorShortcuts.settingDescription)
        #expect(!note.contains("確定+挿入キー"))
        #expect(!note.contains("確定+送信キー"))
        #expect(!note.contains("確定"))
    }

    @Test("AC-5: ノートモードで押せなくする項目の理由の一文は、どれも「ノートモード」を含む")
    func restrictionReasonsMentionNoteMode() {
        for restriction in NoteModeRestriction.allCases {
            #expect(restriction.reason.contains("ノートモード"))
        }
        #expect(AppMode.insert.displayName == "インサートモード")
        #expect(AppMode.note.displayName == "ノートモード")
    }
}
