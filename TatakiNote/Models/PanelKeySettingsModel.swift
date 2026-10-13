import Foundation
import Observation

/// 記録ボックスに出す中身。
enum PanelShortcutRecorderDisplay: Equatable {
    case recording
    case registered(text: String, caps: [String])
    case unregistered

    /// 読み上げに使う値。
    var accessibilityValue: String {
        switch self {
        case .recording: String(localized: "ショートカットを押す")
        case .registered(let text, _): text
        case .unregistered: String(localized: "登録なし")
        }
    }
}

/// 記録ボックスが受け付けた・受け付けなかった合図。`sequence` は合図のたびに増える。
struct RecorderFeedback: Equatable {
    enum Kind: Equatable {
        case accepted
        case rejected
    }

    let kind: Kind
    let sequence: Int
}

/// 設定画面の「確定+挿入キー」「確定+送信キー」の記録ボックスの状態。
@Observable final class PanelKeySettingsModel {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotkey: () -> PanelShortcut?
    @ObservationIgnored private let pauseHotkey: () -> Void
    @ObservationIgnored private let resumeHotkey: () -> Void
    @ObservationIgnored private let setHotkey: (PanelShortcut?) -> Void
    @ObservationIgnored private var lastAcceptedHotkey: PanelShortcut?
    @ObservationIgnored private var feedbackSequence = 0

    private(set) var recordingRole: PanelShortcutRole?
    private(set) var hotkeyRejectionMessage: String?
    private(set) var feedback: [PanelShortcutRole: RecorderFeedback] = [:]
    private(set) var hotkeyFeedback: RecorderFeedback?

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

    /// 「パネルを開く・閉じる」の記録ボックスの変更を受け、⌘K・⌘S・⌘N・⌘B・⌘, なら直前のキーに戻して理由を出す。
    func hotkeyDidChange(to shortcut: PanelShortcut?) {
        guard shortcut != lastAcceptedHotkey else { return }
        if let shortcut, ReservedPanelKeys.isReserved(shortcut) {
            hotkeyRejectionMessage = PanelShortcutRejection.reservedForPanelCommands.message(for: shortcut)
            hotkeyFeedback = makeFeedback(.rejected)
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

    /// 記録ボックスに出す中身(記録中・登録あり・登録なし)。
    func recorderDisplay(for role: PanelShortcutRole) -> PanelShortcutRecorderDisplay {
        if recordingRole == role {
            return .recording
        }
        guard let text = displayText(for: role) else {
            return .unregistered
        }
        return .registered(text: text, caps: KeyCaps.caps(in: text))
    }

    private func makeFeedback(_ kind: RecorderFeedback.Kind) -> RecorderFeedback {
        feedbackSequence += 1
        return RecorderFeedback(kind: kind, sequence: feedbackSequence)
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
            feedback[role] = makeFeedback(.rejected)
            return false
        }
        rejectionMessages[role] = nil
        switch role {
        case .commit: settings.selectCommitKey(candidate.shortcut)
        case .commitAndSend: settings.selectCommitAndSendKey(candidate.shortcut)
        }
        feedback[role] = makeFeedback(.accepted)
        endRecording(role)
        return true
    }

    /// 確定+挿入キーと確定+送信キーの最後の1つを消そうとしたときの理由。
    static let lastKeyClearMessage = String(localized: "確定+挿入キーと確定+送信キーの両方を未登録にはできません。挿入せずに使うときは、ノートモードにしてください。")

    func clear(_ role: PanelShortcutRole) {
        let otherRole: PanelShortcutRole = role == .commit ? .commitAndSend : .commit
        if shortcut(for: otherRole) == nil {
            rejectionMessages[role] = Self.lastKeyClearMessage
            feedback[role] = makeFeedback(.rejected)
            endRecording(role)
            return
        }
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
