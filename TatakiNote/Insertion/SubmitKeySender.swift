import AppKit

/// 挿入先に送信のキー(Enter)を送る。
protocol SubmitKeySending {
    func sendSubmitKey(to target: InsertionTarget) async
}

/// Enter のキーのイベントを送り出す。
protocol SubmitKeyPosting {
    func postSubmitKey()
}

/// いまキーボードで押されている修飾キーの読み取り。
protocol ModifierKeyStateReading {
    var pressedModifiers: CGEventFlags { get }
}

/// いま前面にあるアプリの読み取り。
protocol FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? { get }
}

struct CGEventSubmitKeyPoster: SubmitKeyPosting {
    static func makeEvents() -> (keyDown: CGEvent, keyUp: CGEvent)? {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKey = CGKeyCode(KeyCode.returnKey)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        else { return nil }
        keyDown.flags = []
        keyUp.flags = []
        return (keyDown, keyUp)
    }

    func postSubmitKey() {
        guard let events = Self.makeEvents() else { return }
        events.keyDown.post(tap: .cghidEventTap)
        events.keyUp.post(tap: .cghidEventTap)
    }
}

struct SystemModifierKeyState: ModifierKeyStateReading {
    var pressedModifiers: CGEventFlags {
        CGEventSource.flagsState(.hidSystemState).intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate])
    }
}

struct WorkspaceFrontmostApplication: FrontmostApplicationReading {
    var frontmostProcessIdentifier: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// 修飾キーが離れるのを待ち、前面のアプリが挿入先のままなら Enter を1回送る。
struct EnterKeySender: SubmitKeySending {
    private let poster: SubmitKeyPosting
    private let modifierState: ModifierKeyStateReading
    private let frontmostApp: FrontmostApplicationReading
    private let pollInterval: Duration
    private let maxPolls: Int

    init(
        poster: SubmitKeyPosting = CGEventSubmitKeyPoster(),
        modifierState: ModifierKeyStateReading = SystemModifierKeyState(),
        frontmostApp: FrontmostApplicationReading = WorkspaceFrontmostApplication(),
        pollInterval: Duration = .milliseconds(20),
        maxPolls: Int = 25
    ) {
        self.poster = poster
        self.modifierState = modifierState
        self.frontmostApp = frontmostApp
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    func sendSubmitKey(to target: InsertionTarget) async {
        for _ in 0..<maxPolls {
            if modifierState.pressedModifiers.isEmpty {
                break
            }
            try? await Task.sleep(for: pollInterval)
        }
        guard frontmostApp.frontmostProcessIdentifier == target.processIdentifier else { return }
        poster.postSubmitKey()
    }
}
