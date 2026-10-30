import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct NoteModeKeySettingsTests {
    private func makeModel(settings: AppSettings, recorder: FakeHotkeyController) -> PanelKeySettingsModel {
        PanelKeySettingsModel(
            settings: settings,
            hotkey: { nil },
            pauseHotkey: { recorder.pause() },
            resumeHotkey: { recorder.resume() },
            setHotkey: { _ in }
        )
    }

    private func candidate(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String) -> PanelShortcutCandidate {
        PanelShortcutCandidate(shortcut: PanelShortcut(keyCode: keyCode, modifiers: modifiers), characters: characters)
    }

    // MARK: - AC-8

    @Test("AC-8: もう一方が未登録の確定+挿入キーは消せず、理由が出て、記録は終わる(ホットキーも戻る)")
    func lastCommitKeyIsNotCleared() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        settings.selectCommitAndSendKey(nil)
        let recorder = FakeHotkeyController()
        let model = makeModel(settings: settings, recorder: recorder)

        model.beginRecording(.commit)
        #expect(recorder.pauseCount == 1)
        model.clear(.commit)

        #expect(settings.commitKey == .defaultCommitKey)
        #expect(settings.commitAndSendKey == nil)
        #expect(model.rejectionMessage(for: .commit) == PanelKeySettingsModel.lastKeyClearMessage)
        #expect(model.recordingRole == nil)
        #expect(recorder.resumeCount == 1)
        let reloaded = temp.makeSettings()
        #expect(reloaded.commitKey == .defaultCommitKey)
    }

    @Test("AC-8: もう一方が未登録の確定+送信キーも消せず、理由が出る(記録していなくても理由は出る)")
    func lastCommitAndSendKeyIsNotCleared() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        settings.selectCommitKey(nil)
        let recorder = FakeHotkeyController()
        let model = makeModel(settings: settings, recorder: recorder)

        model.clear(.commitAndSend)

        #expect(settings.commitAndSendKey == .defaultCommitAndSendKey)
        #expect(settings.commitKey == nil)
        #expect(model.rejectionMessage(for: .commitAndSend) == PanelKeySettingsModel.lastKeyClearMessage)
        #expect(model.rejectionMessage(for: .commit) == nil)
        #expect(recorder.pauseCount == 0)
        #expect(recorder.resumeCount == 0)
    }

    @Test("AC-8: もう一方が登録済みなら今までどおり消せ、理由は出ない")
    func keyIsClearedWhenOtherIsRegistered() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        let recorder = FakeHotkeyController()
        let model = makeModel(settings: settings, recorder: recorder)

        model.beginRecording(.commit)
        model.clear(.commit)

        #expect(settings.commitKey == nil)
        #expect(settings.commitAndSendKey == .defaultCommitAndSendKey)
        #expect(model.rejectionMessage(for: .commit) == nil)
        #expect(model.recordingRole == nil)
        #expect(recorder.resumeCount == 1)
    }

    @Test("AC-8: 最後の1つが残っていても、もう一方は登録できる。登録すると理由は消える")
    func otherKeyCanBeRegisteredWhileLastKeyRemains() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }
        let settings = temp.makeSettings()
        settings.selectCommitAndSendKey(nil)
        let recorder = FakeHotkeyController()
        let model = makeModel(settings: settings, recorder: recorder)

        model.clear(.commit)
        #expect(model.rejectionMessage(for: .commit) != nil)

        model.beginRecording(.commitAndSend)
        let accepted = model.record(candidate(keyCode: 38, modifiers: [.command], characters: "j"), for: .commitAndSend)

        #expect(accepted)
        #expect(settings.commitAndSendKey == PanelShortcut(keyCode: 38, modifiers: [.command]))
        #expect(settings.commitKey == .defaultCommitKey)

        model.beginRecording(.commit)
        #expect(model.rejectionMessage(for: .commit) == nil)
        model.clear(.commit)
        #expect(settings.commitKey == nil)
        #expect(model.rejectionMessage(for: .commit) == nil)
    }
}
