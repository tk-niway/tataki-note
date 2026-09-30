import Observation

/// @note p0-341
@Observable final class PanelKeySettingsModel {
    @ObservationIgnored private let settings: AppSettings
    /// @note p0-342
    @ObservationIgnored private let hotkey: () -> PanelShortcut?
    @ObservationIgnored private let pauseHotkey: () -> Void
    @ObservationIgnored private let resumeHotkey: () -> Void

    /// @note p0-343
    private(set) var recordingRole: PanelShortcutRole?

    /// @note p0-344
    private var rejectionMessages: [PanelShortcutRole: String] = [:]

    init(
        settings: AppSettings,
        hotkey: @escaping () -> PanelShortcut? = PanelShortcut.currentHotkey,
        pauseHotkey: @escaping () -> Void = PanelShortcut.pauseHotkey,
        resumeHotkey: @escaping () -> Void = PanelShortcut.resumeHotkey
    ) {
        self.settings = settings
        self.hotkey = hotkey
        self.pauseHotkey = pauseHotkey
        self.resumeHotkey = resumeHotkey
    }

    func shortcut(for role: PanelShortcutRole) -> PanelShortcut? {
        switch role {
        case .commit: settings.commitKey
        case .commitAndSend: settings.commitAndSendKey
        }
    }

    /// @note p0-345
    func displayText(for role: PanelShortcutRole) -> String? {
        shortcut(for: role)?.displayText
    }

    func rejectionMessage(for role: PanelShortcutRole) -> String? {
        rejectionMessages[role]
    }

    /// @note p0-346
    func beginRecording(_ role: PanelShortcutRole) {
        rejectionMessages[role] = nil
        if recordingRole == nil {
            pauseHotkey()
        }
        recordingRole = role
    }

    /// @note p0-347
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

    /// @note p0-348
    func clear(_ role: PanelShortcutRole) {
        rejectionMessages[role] = nil
        switch role {
        case .commit: settings.selectCommitKey(nil)
        case .commitAndSend: settings.selectCommitAndSendKey(nil)
        }
        endRecording(role)
    }

    /// @note p0-349
    func endRecording(_ role: PanelShortcutRole) {
        guard recordingRole == role else { return }
        recordingRole = nil
        resumeHotkey()
    }
}
