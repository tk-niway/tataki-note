import AppKit
import Testing
@testable import TatakiNote

@MainActor
private final class FakeHotkeyController {
    var hotkey: PanelShortcut?
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0

    init(hotkey: PanelShortcut? = nil) {
        self.hotkey = hotkey
    }

    func currentHotkey() -> PanelShortcut? { hotkey }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
}

@MainActor
struct PanelKeySettingsModelTests {
    private func makeSettings() throws -> (settings: AppSettings, defaults: UserDefaults, name: String) {
        let temp = try TemporaryDefaults()
        return (temp.makeSettings(), temp.defaults, temp.name)
    }

    private func makeModel(
        settings: AppSettings,
        controller: FakeHotkeyController? = nil
    ) -> PanelKeySettingsModel {
        let controller = controller ?? FakeHotkeyController()
        return PanelKeySettingsModel(
            settings: settings,
            hotkey: { controller.currentHotkey() },
            pauseHotkey: { controller.pause() },
            resumeHotkey: { controller.resume() }
        )
    }

    private func candidate(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String) -> PanelShortcutCandidate {
        PanelShortcutCandidate(shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers), characters: characters)
    }

    @Test("AC-1: 初期の表記は確定が ⇧⌘↩・確定+送信が ⌘↩")
    func initialDisplayTextIsNewDefault() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        #expect(model.displayText(for: .commit) == "⇧⌘↩")
        #expect(model.displayText(for: .commitAndSend) == "⌘↩")
    }

    @Test("AC-9: 旧キーを保存している人は、読み替えた表記が出る")
    func legacyKeysAreReadAsDisplayText() throws {
        let (_, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("shiftEnter", forKey: "commitKey")
        defaults.set("commandShiftEnter", forKey: "commitAndSendKey")

        let settings = AppSettings(store: SettingsStore(defaults: defaults))
        let model = makeModel(settings: settings)

        #expect(model.displayText(for: .commit) == "⇧↩")
        #expect(model.displayText(for: .commitAndSend) == "⇧⌘↩")
    }

    @Test("AC-11: 修飾キー付きのキーを受け付けると保存され、作り直した AppSettings でも残る")
    func acceptedShortcutIsSavedAndSurvivesRecreation() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        let accepted = model.record(candidate(keyCode: 40, modifiers: [.command], characters: "k"), for: .commit)

        #expect(accepted)
        #expect(model.displayText(for: .commit) == "⌘K")
        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.commitKey == PanelShortcut(keyCode: 40, modifiers: [.command]))
    }

    @Test("AC-12: 修飾キーを含まないキーは受け付けず、値は変わらず理由が出る")
    func missingModifierIsRejectedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        let before = model.displayText(for: .commit)
        let accepted = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)

        #expect(!accepted)
        #expect(model.displayText(for: .commit) == before)
        #expect(model.rejectionMessage(for: .commit) != nil)
    }

    @Test("ホットキーと同じキーは受け付けず、理由が出る")
    func hotkeyCollisionIsRejectedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        let controller = FakeHotkeyController(hotkey: hotkey)
        let model = makeModel(settings: settings, controller: controller)

        let before = model.displayText(for: .commit)
        let accepted = model.record(PanelShortcutCandidate(shortcut: hotkey, characters: " "), for: .commit)

        #expect(!accepted)
        #expect(model.displayText(for: .commit) == before)
        #expect(model.rejectionMessage(for: .commit)?.contains("パネルを開く・閉じる") == true)
    }

    @Test("もう一方で使っているキーは受け付けず、理由が出る")
    func otherRoleCollisionIsRejectedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        let before = model.displayText(for: .commit)
        let accepted = model.record(candidate(keyCode: 36, modifiers: [.command], characters: "\r"), for: .commit)

        #expect(!accepted)
        #expect(model.displayText(for: .commit) == before)
        #expect(model.rejectionMessage(for: .commit)?.contains("確定+送信") == true)
    }

    @Test("AC-15: 入力欄の編集ショートカットは受け付けず、理由が出る")
    func editingShortcutIsRejectedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        let accepted = model.record(candidate(keyCode: 8, modifiers: [.command], characters: "c"), for: .commit)

        #expect(!accepted)
        #expect(model.rejectionMessage(for: .commit) != nil)
    }

    @Test("AC-7: ⌘H は受け付けず、理由が「パネルを閉じるキーのため」になり、登録してあるキーは保存し直しても変わらない")
    func commandHIsRejectedAndKeepsRegisteredKeys() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)
        let message = "⌘H はパネルを閉じるキーのため、登録できません。"

        for role in PanelShortcutRole.allCases {
            let accepted = model.record(candidate(keyCode: 4, modifiers: [.command], characters: "h"), for: role)

            #expect(!accepted, "\(role)")
            #expect(model.rejectionMessage(for: role) == message, "\(role)")
        }

        #expect(model.displayText(for: .commit) == "⇧⌘↩")
        #expect(model.displayText(for: .commitAndSend) == "⌘↩")
        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.commitKey == PanelShortcut.defaultCommitKey)
        #expect(reloaded.commitAndSendKey == PanelShortcut.defaultCommitAndSendKey)
    }

    @Test("AC-30: 修飾キー付きの Esc は受け付けず、理由が出る")
    func modifiedEscapeIsRejectedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        let accepted = model.record(candidate(keyCode: 53, modifiers: [.shift], characters: "\u{1b}"), for: .commit)

        #expect(!accepted)
        #expect(model.rejectionMessage(for: .commit)?.contains("閉じるキー") == true)
    }

    @Test("AC-28: 理由は、次に受け付けた・消した・記録を始め直したときに消える")
    func rejectionMessageClearsOnNextOutcome() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }

        do {
            let model = makeModel(settings: settings)
            model.beginRecording(.commit)
            _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
            #expect(model.rejectionMessage(for: .commit) != nil)
            _ = model.record(candidate(keyCode: 40, modifiers: [.command], characters: "k"), for: .commit)
            #expect(model.rejectionMessage(for: .commit) == nil)
        }

        do {
            let model = makeModel(settings: settings)
            model.beginRecording(.commit)
            _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
            #expect(model.rejectionMessage(for: .commit) != nil)
            model.clear(.commit)
            #expect(model.rejectionMessage(for: .commit) == nil)
        }

        do {
            let model = makeModel(settings: settings)
            model.beginRecording(.commit)
            _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
            #expect(model.rejectionMessage(for: .commit) != nil)
            model.endRecording(.commit)
            #expect(model.rejectionMessage(for: .commit) != nil, "記録をやめただけでは消えない")
            model.beginRecording(.commit)
            #expect(model.rejectionMessage(for: .commit) == nil)
        }
    }

    @Test("AC-17: 消すと登録なしになり panelStatusItems から消える")
    func clearRemovesFromPanelStatusItems() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        #expect(settings.panelStatusItems.contains(.commitAndSend))
        model.clear(.commitAndSend)

        #expect(model.displayText(for: .commitAndSend) == nil)
        #expect(settings.commitAndSendKey == nil)
        #expect(!settings.panelStatusItems.contains(.commitAndSend))
    }

    @Test("ホットキーの閉包は記録のたびに読む(設定画面を開いている間の変更が次の記録から効く)")
    func hotkeyClosureIsReadOnEachRecord() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController(hotkey: nil)
        let model = makeModel(settings: settings, controller: controller)

        let key = PanelShortcut(keyCode: 40, modifiers: [.command])
        #expect(model.record(PanelShortcutCandidate(shortcut: key, characters: "k"), for: .commit))

        controller.hotkey = key
        model.clear(.commit)
        let accepted = model.record(PanelShortcutCandidate(shortcut: key, characters: "k"), for: .commit)
        #expect(!accepted)
    }

    @Test("AC-27: endRecording では値も理由も変わらず recordingRole が nil になる")
    func endRecordingLeavesValueAndMessageUnchanged() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        model.beginRecording(.commit)
        _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
        let messageBefore = model.rejectionMessage(for: .commit)
        let valueBefore = model.displayText(for: .commit)

        model.endRecording(.commit)

        #expect(model.recordingRole == nil)
        #expect(model.rejectionMessage(for: .commit) == messageBefore)
        #expect(model.displayText(for: .commit) == valueBefore)
    }

    @Test("AC-29: 記録を始めるとホットキーを1回止め、記録の終わり方(受け付けた・clear・endRecording)のどれでも1回戻す")
    func hotkeyPauseAndResumeCountsBalance() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.beginRecording(.commit)
            #expect(controller.pauseCount == 1)
            _ = model.record(candidate(keyCode: 40, modifiers: [.command], characters: "k"), for: .commit)
            #expect(controller.resumeCount == 1)
            model.clear(.commit)
        }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.beginRecording(.commit)
            #expect(controller.pauseCount == 1)
            _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
            #expect(controller.resumeCount == 0)
            model.endRecording(.commit)
            #expect(controller.resumeCount == 1)
        }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.beginRecording(.commit)
            model.clear(.commit)
            #expect(controller.pauseCount == 1)
            #expect(controller.resumeCount == 1)
        }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.beginRecording(.commit)
            model.endRecording(.commit)
            #expect(controller.pauseCount == 1)
            #expect(controller.resumeCount == 1)
        }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.beginRecording(.commit)
            model.beginRecording(.commitAndSend)
            #expect(controller.pauseCount == 1)
            model.endRecording(.commitAndSend)
            #expect(controller.resumeCount == 1)
        }

        do {
            let controller = FakeHotkeyController()
            let model = makeModel(settings: settings, controller: controller)
            model.endRecording(.commit)
            #expect(controller.pauseCount == 0)
            #expect(controller.resumeCount == 0)
            model.clear(.commit)
            #expect(controller.pauseCount == 0)
            #expect(controller.resumeCount == 0)
        }
    }
}
