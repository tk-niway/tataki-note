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
    func set(_ shortcut: PanelShortcut?) {
        hotkey = shortcut
        setCalls.append(shortcut)
    }

    private(set) var setCalls: [PanelShortcut?] = []
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
            resumeHotkey: { controller.resume() },
            setHotkey: { controller.set($0) }
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

        let accepted = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commit)

        #expect(accepted)
        #expect(model.displayText(for: .commit) == "⌘J")
        let reloaded = AppSettings(store: SettingsStore(defaults: defaults))
        #expect(reloaded.commitKey == PanelShortcut(keyCode: 38, modifiers: [.command]))
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
            _ = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commit)
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

        let key = PanelShortcut(keyCode: 38, modifiers: [.command])
        #expect(model.record(PanelShortcutCandidate(shortcut: key, characters: "j"), for: .commit))

        controller.hotkey = key
        model.clear(.commit)
        let accepted = model.record(PanelShortcutCandidate(shortcut: key, characters: "j"), for: .commit)
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

    @Test("AC-10: 「パネルを開く・閉じる」で ⌘K・⌘S・⌘N・⌘B・⌘, を押すと直前のキーに戻り、理由が出る")
    func reservedHotkeyIsRevertedWithMessage() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])

        for (keyCode, label) in [(UInt16(40), "⌘K"), (UInt16(1), "⌘S"), (UInt16(45), "⌘N"), (UInt16(11), "⌘B"), (UInt16(43), "⌘,")] {
            let controller = FakeHotkeyController(hotkey: previous)
            let model = makeModel(settings: settings, controller: controller)
            let reserved = PanelShortcut(keyCode: keyCode, modifiers: [.command])

            controller.hotkey = reserved
            model.hotkeyDidChange(to: reserved)

            #expect(controller.setCalls == [previous], "\(label)")
            #expect(controller.hotkey == previous, "\(label)")
            #expect(model.hotkeyRejectionMessage?.contains(label) == true, "\(label)")
            #expect(model.hotkeyRejectionMessage?.contains("登録できません") == true, "\(label)")
        }
    }

    @Test("AC-10: 拒否して直前のキーに戻した通知では理由は消えず、受け付けるキーを押すと消える")
    func hotkeyRejectionSurvivesRevertNotificationAndClearsOnAcceptedKey() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        let controller = FakeHotkeyController(hotkey: previous)
        let model = makeModel(settings: settings, controller: controller)

        model.hotkeyDidChange(to: PanelShortcut(keyCode: 40, modifiers: [.command]))
        let message = model.hotkeyRejectionMessage
        #expect(message != nil)

        model.hotkeyDidChange(to: previous)
        #expect(model.hotkeyRejectionMessage == message)
        #expect(controller.setCalls.count == 1)

        let accepted = PanelShortcut(keyCode: 38, modifiers: [.command])
        model.hotkeyDidChange(to: accepted)
        #expect(model.hotkeyRejectionMessage == nil)
        #expect(controller.setCalls.count == 1)

        model.hotkeyDidChange(to: PanelShortcut(keyCode: 1, modifiers: [.command]))
        #expect(controller.setCalls == [previous, accepted], "直前のキーは受け付けたキーに更新される")
    }

    @Test("AC-10: 修飾キーが違う ⇧⌘K は予約に当たらず受け付ける")
    func nonReservedHotkeyIsAccepted() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController(hotkey: nil)
        let model = makeModel(settings: settings, controller: controller)

        model.hotkeyDidChange(to: PanelShortcut(keyCode: 40, modifiers: [.command, .shift]))

        #expect(model.hotkeyRejectionMessage == nil)
        #expect(controller.setCalls.isEmpty)
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
            _ = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commit)
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

    @Test("AC-31: 記録ボックスは、登録があればキーキャップに分けた表記、無ければ登録なし、記録中は記録中の表示になり、読み上げの値も同じ")
    func recorderDisplayShowsRegisteredUnregisteredAndRecording() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        #expect(model.recorderDisplay(for: .commit) == .registered(text: "⇧⌘↩", caps: ["⇧", "⌘", "↩"]))
        #expect(model.recorderDisplay(for: .commitAndSend) == .registered(text: "⌘↩", caps: ["⌘", "↩"]))
        #expect(model.recorderDisplay(for: .commit).accessibilityValue == "⇧⌘↩")

        model.clear(.commit)
        #expect(model.recorderDisplay(for: .commit) == .unregistered)
        #expect(model.recorderDisplay(for: .commit).accessibilityValue == "登録なし")
        #expect(model.recorderDisplay(for: .commitAndSend) == .registered(text: "⌘↩", caps: ["⌘", "↩"]))

        model.beginRecording(.commit)
        #expect(model.recorderDisplay(for: .commit) == .recording)
        #expect(model.recorderDisplay(for: .commit).accessibilityValue == "ショートカットを押す")
        #expect(model.recorderDisplay(for: .commitAndSend) == .registered(text: "⌘↩", caps: ["⌘", "↩"]))
    }

    @Test("AC-31: 新しく記録したキーは、修飾キーと残りに分けた表示になる")
    func recorderDisplayFollowsRecordedShortcut() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        model.beginRecording(.commit)
        _ = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commit)

        #expect(model.recorderDisplay(for: .commit) == .registered(text: "⌘J", caps: ["⌘", "J"]))
    }

    @Test("AC-32: 受け付けると受け付けた合図が出て、受け付けないと受け付けなかった合図が出る。合図のたびに sequence が増える")
    func recordEmitsAcceptedAndRejectedFeedback() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        #expect(model.feedback[.commit] == nil)

        model.beginRecording(.commit)
        _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
        let rejected = try #require(model.feedback[.commit])
        #expect(rejected.kind == .rejected)

        _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
        let rejectedAgain = try #require(model.feedback[.commit])
        #expect(rejectedAgain.kind == .rejected)
        #expect(rejectedAgain.sequence > rejected.sequence)

        _ = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commit)
        let accepted = try #require(model.feedback[.commit])
        #expect(accepted.kind == .accepted)
        #expect(accepted.sequence > rejectedAgain.sequence)

        model.beginRecording(.commit)
        _ = model.record(candidate(keyCode: 38, modifiers: [.command, .shift], characters: "j"), for: .commit)
        let acceptedAgain = try #require(model.feedback[.commit])
        #expect(acceptedAgain.kind == .accepted)
        #expect(acceptedAgain.sequence > accepted.sequence)
        #expect(model.feedback[.commitAndSend] == nil)
    }

    @Test("AC-32: 受け付けないキーは、どの理由でも値が変わらず理由と受け付けなかった合図が出る")
    func everyRejectionReasonKeepsValueAndEmitsRejectedFeedback() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let hotkey = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        let model = makeModel(settings: settings, controller: FakeHotkeyController(hotkey: hotkey))

        let rejectedCandidates: [(label: String, candidate: PanelShortcutCandidate)] = [
            ("修飾キーなし", candidate(keyCode: 40, modifiers: [], characters: "k")),
            ("編集ショートカット ⌘C", candidate(keyCode: 8, modifiers: [.command], characters: "c")),
            ("もう一方のキー ⌘↩", candidate(keyCode: 36, modifiers: [.command], characters: "\r")),
            ("ホットキー", PanelShortcutCandidate(shortcut: hotkey, characters: " ")),
            ("⌘H", candidate(keyCode: 4, modifiers: [.command], characters: "h")),
            ("修飾つき esc", candidate(keyCode: 53, modifiers: [.shift], characters: "\u{1b}")),
        ]

        var lastSequence = 0
        for (label, rejectedCandidate) in rejectedCandidates {
            model.beginRecording(.commit)
            let accepted = model.record(rejectedCandidate, for: .commit)

            #expect(!accepted, "\(label)")
            #expect(model.displayText(for: .commit) == "⇧⌘↩", "\(label)")
            #expect(model.rejectionMessage(for: .commit) != nil, "\(label)")
            let feedback = try #require(model.feedback[.commit], "\(label)")
            #expect(feedback.kind == .rejected, "\(label)")
            #expect(feedback.sequence > lastSequence, "\(label)")
            lastSequence = feedback.sequence
        }
    }

    @Test("AC-32: 最後の1つを消そうとすると理由と受け付けなかった合図が出る。もう一方が登録済みなら消せて合図は出ない")
    func clearingLastKeyEmitsRejectedFeedback() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings)

        model.clear(.commit)
        #expect(model.displayText(for: .commit) == nil)
        #expect(model.feedback[.commit] == nil)
        #expect(model.rejectionMessage(for: .commit) == nil)

        model.beginRecording(.commitAndSend)
        model.clear(.commitAndSend)

        #expect(model.displayText(for: .commitAndSend) == "⌘↩")
        #expect(model.rejectionMessage(for: .commitAndSend) == PanelKeySettingsModel.lastKeyClearMessage)
        #expect(model.feedback[.commitAndSend]?.kind == .rejected)
    }

    @Test("AC-33: 窓を開いた直後は記録が始まっておらず、押して初めて記録中になる")
    func recordingDoesNotStartUntilBegun() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController()
        let model = makeModel(settings: settings, controller: controller)

        #expect(model.recordingRole == nil)
        #expect(controller.pauseCount == 0)
        for role in PanelShortcutRole.allCases {
            #expect(model.recorderDisplay(for: role) != .recording)
        }

        model.beginRecording(.commit)

        #expect(model.recordingRole == .commit)
        #expect(model.recorderDisplay(for: .commit) == .recording)
        #expect(controller.pauseCount == 1)
    }

    @Test("AC-33: esc で取り消すと値は元のまま待ちに戻り、止めていたホットキーが戻る")
    func cancelRestoresDisplayAndResumesHotkey() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController()
        let model = makeModel(settings: settings, controller: controller)

        model.beginRecording(.commit)
        model.endRecording(.commit)

        #expect(model.recordingRole == nil)
        #expect(model.recorderDisplay(for: .commit) == .registered(text: "⇧⌘↩", caps: ["⇧", "⌘", "↩"]))
        #expect(model.feedback[.commit] == nil)
        #expect(controller.pauseCount == 1)
        #expect(controller.resumeCount == 1)
    }

    @Test("AC-33: Delete で登録を外すと登録なしの待ちに戻り、ホットキーが戻る")
    func deleteClearsRegistrationAndResumesHotkey() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController()
        let model = makeModel(settings: settings, controller: controller)

        model.beginRecording(.commit)
        model.clear(.commit)

        #expect(model.recordingRole == nil)
        #expect(model.recorderDisplay(for: .commit) == .unregistered)
        #expect(controller.resumeCount == 1)
    }

    @Test("AC-33: 受け付けないキーのあとに外のクリックや種類の切り替えで終えると、値は元のままホットキーが戻る")
    func endingAfterRejectionRestoresHotkeyAndKeepsValue() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController()
        let model = makeModel(settings: settings, controller: controller)

        model.beginRecording(.commit)
        _ = model.record(candidate(keyCode: 40, modifiers: [], characters: "k"), for: .commit)
        #expect(model.recorderDisplay(for: .commit) == .recording)
        #expect(controller.resumeCount == 0)

        model.endRecording(.commit)

        #expect(model.recorderDisplay(for: .commit) == .registered(text: "⇧⌘↩", caps: ["⇧", "⌘", "↩"]))
        #expect(controller.resumeCount == 1)
    }

    @Test("AC-33: もう一方の箱を押すと、そちらが記録中になり、元の箱は待ちに戻る")
    func beginningOtherRecorderMovesRecording() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = FakeHotkeyController()
        let model = makeModel(settings: settings, controller: controller)

        model.beginRecording(.commit)
        model.endRecording(.commit)
        model.beginRecording(.commitAndSend)

        #expect(model.recorderDisplay(for: .commit) == .registered(text: "⇧⌘↩", caps: ["⇧", "⌘", "↩"]))
        #expect(model.recorderDisplay(for: .commitAndSend) == .recording)
        #expect(controller.pauseCount == 2)
        #expect(controller.resumeCount == 1)
    }

    @Test("AC-34: ホットキーに ⌘K・⌘S・⌘N・⌘B・⌘, を記録すると直前のキーに戻り、理由と受け付けなかった合図が出る")
    func reservedHotkeyEmitsRejectedFeedback() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = PanelShortcut(keyCode: 49, modifiers: [.option, .shift])
        let controller = FakeHotkeyController(hotkey: previous)
        let model = makeModel(settings: settings, controller: controller)

        #expect(model.hotkeyFeedback == nil)

        var lastSequence = 0
        for (keyCode, label) in [(UInt16(40), "⌘K"), (UInt16(1), "⌘S"), (UInt16(45), "⌘N"), (UInt16(11), "⌘B"), (UInt16(43), "⌘,")] {
            let reserved = PanelShortcut(keyCode: keyCode, modifiers: [.command])
            controller.hotkey = reserved
            model.hotkeyDidChange(to: reserved)

            #expect(controller.hotkey == previous, "\(label)")
            #expect(model.hotkeyRejectionMessage != nil, "\(label)")
            let feedback = try #require(model.hotkeyFeedback, "\(label)")
            #expect(feedback.kind == .rejected, "\(label)")
            #expect(feedback.sequence > lastSequence, "\(label)")
            lastSequence = feedback.sequence

            model.hotkeyDidChange(to: previous)
            #expect(model.hotkeyFeedback?.sequence == lastSequence, "\(label): 戻した通知で合図は増えない")
        }
    }

    @Test("AC-34: 予約に当たらないホットキーでは合図を出さない")
    func acceptedHotkeyEmitsNoFeedback() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(settings: settings, controller: FakeHotkeyController(hotkey: nil))

        model.hotkeyDidChange(to: PanelShortcut(keyCode: 40, modifiers: [.command, .shift]))

        #expect(model.hotkeyFeedback == nil)
    }
}
