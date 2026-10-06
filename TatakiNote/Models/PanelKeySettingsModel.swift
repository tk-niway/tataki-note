import Observation

/// 設定画面の「確定+挿入キー」「確定+送信キー」の記録ボックスの状態。
@Observable final class PanelKeySettingsModel {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotkey: () -> PanelShortcut?
    @ObservationIgnored private let pauseHotkey: () -> Void
    @ObservationIgnored private let resumeHotkey: () -> Void
    @ObservationIgnored private let setHotkey: (PanelShortcut?) -> Void
    @ObservationIgnored private var lastAcceptedHotkey: PanelShortcut?

    private(set) var recordingRole: PanelShortcutRole?
    private(set) var hotkeyRejectionMessage: String?

    private var rejectionMessages: [PanelShortcutRole: String] = [:]

    init(
        settings: AppSettings,
        hotkey: @escaping () -> PanelShortcut? = PanelShortcut.currentHotkey,
        pauseHotkey: @escaping () -> Void = PanelShortcut.pauseHotkey,
        resumeHotkey: @escaping () -> Void = PanelShortcut.resumeHotkey,
        setHotkey: @escaping (PanelShortcut?) -> Void = PanelShortcut.setHotkey
    ) {
        self.settings = settings
        self.hotkey = hotkey
        self.pauseHotkey = pauseHotkey
        self.resumeHotkey = resumeHotkey
        self.setHotkey = setHotkey
        self.lastAcceptedHotkey = hotkey()
    }

    /// 「パネルを開く・閉じる」の記録ボックスの変更を受け、⌘K・⌘S・⌘N なら直前のキーに戻して理由を出す。
    func hotkeyDidChange(to shortcut: PanelShortcut?) {
        guard shortcut != lastAcceptedHotkey else { return }
        if let shortcut, ReservedPanelKeys.isReserved(shortcut) {
            hotkeyRejectionMessage = PanelShortcutRejection.reservedForPanelCommands.message(for: shortcut)
            setHotkey(lastAcceptedHotkey)
            return
        }
        hotkeyRejectionMessage = nil
        lastAcceptedHotkey = shortcut
    }

    func shortcut(for role: PanelShortcutRole) -> PanelShortcut? {
        switch role {
        case .commit: settings.commitKey
        case .commitAndSend: settings.commitAndSendKey
        }
    }

    func displayText(for role: PanelShortcutRole) -> String? {
        shortcut(for: role)?.displayText
    }

    func rejectionMessage(for role: PanelShortcutRole) -> String? {
        rejectionMessages[role]
    }

    func beginRecording(_ role: PanelShortcutRole) {
        rejectionMessages[role] = nil
        if recordingRole == nil {
            pauseHotkey()
        }
        recordingRole = role
    }

    @discardableResult
    func record(_ candidate: PanelShortcutCandidate, for role: PanelShortcutRole) -> Bool {
        let rejection = PanelShortcutRules.rejection(
            for: candidate,
            role: role,
            hotkey: hotkey(),
            commitKey: settings.commitKey,
            commitAndSendKey: settings.commitAndSendKey
        )
        if let rejection {
            rejectionMessages[role] = rejection.message(for: candidate.shortcut)
            return false
        }
        rejectionMessages[role] = nil
        switch role {
        case .commit: settings.selectCommitKey(candidate.shortcut)
        case .commitAndSend: settings.selectCommitAndSendKey(candidate.shortcut)
        }
        endRecording(role)
        return true
    }

    func clear(_ role: PanelShortcutRole) {
        rejectionMessages[role] = nil
        switch role {
        case .commit: settings.selectCommitKey(nil)
        case .commitAndSend: settings.selectCommitAndSendKey(nil)
        }
        endRecording(role)
    }

    func endRecording(_ role: PanelShortcutRole) {
        guard recordingRole == role else { return }
        recordingRole = nil
        resumeHotkey()
    }
}
